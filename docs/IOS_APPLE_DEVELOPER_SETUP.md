# Apple Developer + GitHub Setup

## Required Apple items

1. Enroll in the Apple Developer Program.
2. Choose a unique bundle ID, e.g. `com.yourname.hudwaycontroller`.
3. Register that App ID in Certificates, Identifiers & Profiles.
4. For Ad Hoc installation:
   - register your iPhone UDID;
   - create an Apple Distribution certificate;
   - create an Ad Hoc provisioning profile containing that device.
5. For TestFlight:
   - create an App Store Connect app record using the same bundle ID;
   - create an App Store Connect provisioning profile;
   - create an App Store Connect API key.

## GitHub Actions secrets

Common:
- `APPLE_TEAM_ID`
- `IOS_BUNDLE_ID`
- `IOS_DISTRIBUTION_P12_BASE64`
- `IOS_DISTRIBUTION_P12_PASSWORD`

Ad Hoc:
- `IOS_ADHOC_PROFILE_BASE64`

TestFlight:
- `IOS_APPSTORE_PROFILE_BASE64`
- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_KEY_P8_BASE64`

### Base64 files on Windows PowerShell

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("certificate.p12")) | Set-Content cert-base64.txt
[Convert]::ToBase64String([IO.File]::ReadAllBytes("HUDWAY_AdHoc.mobileprovision")) | Set-Content adhoc-base64.txt
[Convert]::ToBase64String([IO.File]::ReadAllBytes("HUDWAY_AppStore.mobileprovision")) | Set-Content appstore-base64.txt
[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXXXXXXXX.p8")) | Set-Content asc-key-base64.txt
```

Paste the one-line text into the matching GitHub secret.

## Recommended first installation path: TestFlight

TestFlight is the easiest no-Mac installation workflow:
1. Push the iOS project.
2. Confirm `iOS CI` passes.
3. Complete the signing/App Store Connect setup.
4. Run `Build and Upload iOS TestFlight`.
5. In App Store Connect, add yourself as an internal tester.
6. Install Apple's TestFlight app on the iPhone and install HUDWAY Controller.

## Ad Hoc alternative

Run `Build Signed iOS Ad Hoc IPA` after registering the phone and creating the
Ad Hoc provisioning profile. The resulting IPA is limited to UDIDs included in
that profile. GitHub produces the IPA, but iOS still requires an approved
installation channel/tool; TestFlight avoids this extra sideload step.


## Create the Apple Distribution certificate on Windows (no Mac required)

Install OpenSSL (Git for Windows includes an OpenSSL binary, or install a normal
OpenSSL distribution), then keep the private key private:

```powershell
openssl genrsa -out hudway_distribution.key 2048
openssl req -new -key hudway_distribution.key `
  -out CertificateSigningRequest.certSigningRequest `
  -subj "/CN=YOUR LEGAL NAME/emailAddress=YOUR_APPLE_ID_EMAIL/C=US"
```

In Apple Developer → Certificates, create an **Apple Distribution** certificate
and upload `CertificateSigningRequest.certSigningRequest`. Download the resulting
`.cer`, then:

```powershell
openssl x509 -inform DER -in distribution.cer -out distribution.pem
openssl pkcs12 -export `
  -inkey hudway_distribution.key `
  -in distribution.pem `
  -out HUDWAY_Distribution.p12
```

Choose a strong export password. Put the base64 form of the `.p12` and its
password into GitHub secrets. Never commit the `.key`, `.p12`, `.mobileprovision`,
or `.p8` files to Git.

## Bundle ID suggestion

Use your own reverse-DNS identifier, for example:

`com.<your-name-or-domain>.hudwaycontroller`

Do not use `com.hudway.*` unless HUDWAY specifically grants use of that identifier.
