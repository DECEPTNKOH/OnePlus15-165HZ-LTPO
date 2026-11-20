import java.io.*;
import java.nio.ByteBuffer;
import java.nio.charset.*;
import java.util.*;
import javax.xml.parsers.*;
import org.w3c.dom.*;
import org.xml.sax.*;
import org.xml.sax.helpers.DefaultHandler;

/** Read-only guard for UTF-8 OPlus refresh configs. No Android app context needed. */
public final class XmlGuard {
    private static final int MAX_BYTES = 4 * 1024 * 1024;
    private static final String RATE = "[0-9]-[0-9]-[0-9]-[0-9]";
    private static void require(boolean ok, String reason) throws IOException {
        if (!ok) throw new IOException(reason);
    }

    private static void strictSaxCheck(String text) throws Exception {
        SAXParserFactory factory = SAXParserFactory.newInstance();
        factory.setNamespaceAware(false);
        factory.setValidating(false);
        XMLReader reader = factory.newSAXParser().getXMLReader();
        DefaultHandler handler = new DefaultHandler() {
            public void startElement(String uri, String local, String name,
                                     Attributes attributes) throws SAXException {
                Set<String> seen = new HashSet<String>();
                for (int i = 0; i < attributes.getLength(); i++) {
                    String key = attributes.getQName(i);
                    if (key == null || key.isEmpty() || !seen.add(key)) {
                        throw new SAXException("duplicate/invalid attribute: " + key);
                    }
                }
            }
            public InputSource resolveEntity(String publicId, String systemId)
                    throws SAXException {
                throw new SAXException("external resolution rejected");
            }
            public void error(SAXParseException e) throws SAXException {
                throw e;
            }
            public void fatalError(SAXParseException e) throws SAXException {
                throw e;
            }
        };
        reader.setContentHandler(handler);
        reader.setErrorHandler(handler);
        reader.setEntityResolver(handler);
        reader.parse(new InputSource(new StringReader(text)));
    }

    private static Document load(String path) throws Exception {
        ByteArrayOutputStream data = new ByteArrayOutputStream();
        try (InputStream in = new FileInputStream(path)) {
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) != -1) {
                require(data.size() + n <= MAX_BYTES, "file exceeds 4 MiB");
                data.write(buf, 0, n);
            }
        }
        String text = StandardCharsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(data.toByteArray())).toString();
        require(text.indexOf('\0') < 0, "NUL/UTF-16 input rejected");
        // DTDs are unsupported. Reject before parsing, even inside comments.
        require(!text.contains("<!DOCTYPE") && !text.contains("<!ENTITY"), "DTD/entity declarations rejected");
        if (text.startsWith("\ufeff")) text = text.substring(1);
        strictSaxCheck(text);
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setNamespaceAware(false);
        factory.setValidating(false);
        factory.setExpandEntityReferences(false);
        DocumentBuilder builder = factory.newDocumentBuilder();
        builder.setEntityResolver(new EntityResolver() {
            public InputSource resolveEntity(String publicId, String systemId) throws SAXException {
                throw new SAXException("external resolution rejected");
            }
        });
        builder.setErrorHandler(new DefaultHandler() {
            public void error(SAXParseException e) throws SAXException { throw e; }
            public void fatalError(SAXParseException e) throws SAXException { throw e; }
        });
        Document doc = builder.parse(new InputSource(new StringReader(text)));
        Element root = doc.getDocumentElement();
        require(root != null && root.getTagName().equals("refresh_rate_config"), "wrong root");
        require(root.getAttribute("version").matches("[0-9]+"), "invalid version");
        NodeList configs = root.getElementsByTagName("config");
        require(configs.getLength() == 1, "expected exactly one config");
        Element config = (Element) configs.item(0);
        require(config.getParentNode() == root, "config must be a direct child");
        require(config.getAttribute("defaultRateId").matches(RATE), "invalid defaultRateId");
        NodeList items = root.getElementsByTagName("item");
        require(items.getLength() > 0, "no items");
        require(root.getElementsByTagName("*").getLength() <= 50000, "too many elements");
        for (int i = 0; i < items.getLength(); i++) {
            Element item = (Element) items.item(i);
            require(item.getParentNode() == root, "nested item unsupported");
            require(!item.getAttribute("package").isEmpty(), "item has no package");
            require(item.getAttribute("rateId").matches(RATE), "invalid item rateId");
        }
        return doc;
    }
    private static boolean ignored(String tag, String name) {
        return (tag.equals("refresh_rate_config") && name.equals("version")) ||
            (tag.equals("config") && (name.equals("defaultRateId") || name.equals("defaultMaxRate") || name.equals("highLightCameraRate"))) ||
            (tag.equals("item") && (name.equals("rateId") || name.equals("enableWinOverride")));
    }
    private static String attrs(Element e) {
        TreeMap<String,String> sorted = new TreeMap<String,String>();
        NamedNodeMap map = e.getAttributes();
        for (int i = 0; i < map.getLength(); i++) {
            Node a = map.item(i);
            if (!ignored(e.getTagName(), a.getNodeName())) sorted.put(a.getNodeName(), a.getNodeValue());
        }
        StringBuilder out = new StringBuilder();
        for (Map.Entry<String,String> a : sorted.entrySet()) {
            out.append(a.getKey().length()).append(':').append(a.getKey());
            out.append(a.getValue().length()).append(':').append(a.getValue());
        }
        return out.toString();
    }
    private static String signature(Element e) {
        StringBuilder out = new StringBuilder(e.getTagName()).append('{').append(attrs(e)).append('}');
        for (Node n = e.getFirstChild(); n != null; n = n.getNextSibling()) {
            if (n instanceof Element) {
                String part = signature((Element)n);
                out.append('E').append(part.length()).append(':').append(part);
            } else if (n.getNodeType() == Node.TEXT_NODE || n.getNodeType() == Node.CDATA_SECTION_NODE) {
                String part = n.getNodeValue().trim();
                if (!part.isEmpty()) out.append('T').append(part.length()).append(':').append(part);
            }
        }
        return out.toString();
    }
    private static Map<String,Integer> inventory(Element root) {
        Map<String,Integer> counts = new HashMap<String,Integer>();
        for (Node n = root.getFirstChild(); n != null; n = n.getNextSibling()) {
            if (n instanceof Element) {
                String key = signature((Element)n);
                counts.put(key, counts.containsKey(key) ? counts.get(key) + 1 : 1);
            }
        }
        return counts;
    }
    private static void compare(Document before, Document after) throws Exception {
        Element a = before.getDocumentElement(), b = after.getDocumentElement();
        require(attrs(a).equals(attrs(b)), "unexpected root attribute changes");
        require(b.getAttribute("version").equals("20991231"), "patched version missing");
        Element config = (Element)b.getElementsByTagName("config").item(0);
        require(config.getAttribute("defaultMaxRate").equals("165"), "defaultMaxRate is not 165");
        Map<String,Integer> src = inventory(a), dst = inventory(b);
        for (Map.Entry<String,Integer> entry : src.entrySet()) {
            require(dst.containsKey(entry.getKey()) && dst.get(entry.getKey()) >= entry.getValue(), "source entry lost or unexpectedly modified");
        }
        for (Node n = b.getFirstChild(); n != null; n = n.getNextSibling()) {
            if (!(n instanceof Element)) continue;
            Element e = (Element)n;
            String key = signature(e);
            int old = src.containsKey(key) ? src.get(key) : 0;
            if (dst.get(key) > old) {
                require(e.getTagName().equals("item") || e.getTagName().equals("cameraOverride"), "unexpected added element");
                require(e.getAttribute("package").matches("[A-Za-z_][A-Za-z0-9_]*([.][A-Za-z_][A-Za-z0-9_]*)*"), "invalid added package");
            }
        }
        int high = 0;
        NodeList items = b.getElementsByTagName("item");
        for (int i = 0; i < items.getLength(); i++) {
            if (((Element)items.item(i)).getAttribute("rateId").endsWith("-7")) high++;
        }
        require(high > 0, "no high-rate entries");
    }
    public static void main(String[] args) {
        try {
            require(args.length == 2 || args.length == 3, "usage: XmlGuard check FILE | compare BEFORE AFTER");
            require((args[0].equals("check") && args.length == 2) || (args[0].equals("compare") && args.length == 3), "invalid arguments");
            Document doc = load(args[1]);
            if (args[0].equals("compare")) { Document before = doc; doc = load(args[2]); compare(before, doc); }
            System.out.println("XML_GUARD_OK items=" + doc.getElementsByTagName("item").getLength());
        } catch (Exception e) {
            System.err.println("XML_GUARD_ERROR: " + e.getClass().getSimpleName() + ": " + e.getMessage());
            System.exit(1);
        }
    }
}
