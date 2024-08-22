# apkeep

#### Build the image
```
% docker build -f Dockerfile.apkeep -t apkeep .
```

#### Obtain AAS token via OAuth2
- https://github.com/EFForg/apkeep/blob/master/USAGE-google-play.md
```
# Steps:
1. 
```

#### Obtain AAS token from OAuth Token
```
% docker run --rm apkeep -e 'yourmail@gmail.com' --oauth-token 'oauth2_4/...'
```

#### Download APK from Google Play Store using apkeep + AAS token
```
% docker run --rm -v ./:/output apkeep -a com.xxx.android -d google-play -o device=px_7a -e 'yourmail@gmail.com' -t aas_et/AKppXXXX /output
```
