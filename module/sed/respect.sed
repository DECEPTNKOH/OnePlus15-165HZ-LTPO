/<item/{
s/ rateId="([0-9])-[0-9]-([0-9])-3"/ rateId="\1-3-\2-7"/
s/ rateId="([0-9])-[0-9]-([0-9])-7"/ rateId="\1-3-\2-7"/
s/ rateId="([0-9])-[0-9]-([0-9])-4"/ rateId="\1-3-\2-4"/
s/ rateId="([0-9])-[0-9]-([0-9])-([0125689])"/ rateId="\1-\3-\2-\3"/
}
/<config /{
s/<config /<config defaultMaxRate="165" /
s/(defaultMaxRate="165".*) defaultMaxRate="[0-9]+"/\1/
s/ defaultRateId="([0-9])-[0-9]-([0-9])-3"/ defaultRateId="\1-3-\2-7"/
s/ defaultRateId="([0-9])-[0-9]-([0-9])-7"/ defaultRateId="\1-3-\2-7"/
s/ defaultRateId="([0-9])-[0-9]-([0-9])-4"/ defaultRateId="\1-3-\2-4"/
s/ defaultRateId="([0-9])-[0-9]-([0-9])-([0125689])"/ defaultRateId="\1-\3-\2-\3"/
}
s/(<refresh_rate_config[^>]*version=")[0-9]+(")/\120991231\2/
