# Signing, Notarization & Gatekeeper for a SwiftPM macOS App

Research note. Project context (SwiftPM menu-bar screen-capture app, ad-hoc signed
`Scripts/package_app.sh`, DMG + ZIP published from GitHub Actions on `macos-26`) is taken as
given and is not re-derived here.

Source labels used throughout:

- **official doc** — Apple developer documentation / Apple Support / App Store Connect Help
- **tech note** — Apple Developer Technical Note (TN…)
- **man page** — Apple man page shipped with macOS, Xcode or Command Line Tools
- **forum** — Apple Developer Forums; author noted when they are Apple DTS ("Quinn 'The Eskimo!'")
- **vendor doc** — non-Apple project's own documentation (GitHub, Homebrew, fastlane)

Facts I could not establish from a primary source are called out inline as **UNCONFIRMED** and
collected in the final section. Nothing here was verified by running a build.

---

## Summary / Recommendation

1. **The dialog is a notarization failure, not a "broken signature" failure.** The exact strings in
   the tester's report match Apple's own screenshot for the *"Apple could not verify … is free of
   malware…"* alert, which Apple shows for software it cannot check — i.e. quarantined software that
   is not Developer-ID-signed **and** notarized
   ([Apple Support 102445](https://support.apple.com/en-us/102445), official doc). An ad-hoc
   signature can never satisfy Gatekeeper here, because Gatekeeper wants a Developer ID signature
   plus a notarization ticket. Apple does not publish a mapping from signature state → dialog string,
   so treat the precise classifier as inferred from Apple's own descriptions, not documented.
2. **Minimum fix (paid, and there is no free substitute):** Developer ID Application certificate →
   sign the `.app` with `--options runtime --timestamp --force --sign "Developer ID Application: …"`
   → build the DMG from the signed app → sign the DMG → `xcrun notarytool submit --wait` → `xcrun
   stapler staple`. Developer ID is *strictly required*: Apple states directly that you cannot notarize
   with an ad-hoc, self-signed, Apple Development, or Mac Distribution certificate.
3. **Order of operations.** Apple: sign inside-out, *notarize only the outermost container*, staple the
   distribution file. Quinn (Apple DTS): staple the app as well if the app can reach the user without
   the container being opened by Finder (e.g. mounted with `hdiutil`, or unzipped). Recommended for
   this repo: **two-pass** — notarize+staple the app, then notarize+staple the DMG, and build the ZIP
   from the already-stapled app.
4. **The DMG does not have to be signed to be notarized or stapled** (Apple DTS), but Apple's own
   packaging documentation tells you to sign it, and signing it puts the image itself in the ticket.
   The DMG's signature is *not* what makes the dialog go away.
5. **Ad-hoc + hardened runtime changes nothing for Gatekeeper.** It changes runtime behaviour locally,
   but notarization is impossible without a Developer ID certificate.
6. **No legitimate free path to notarization.** Notarization is gated on a Developer ID certificate,
   which is issued through Certificates, Identifiers & Profiles, which requires Apple Developer
   Program membership — **US$99/year**
   ([Apple Developer Program](https://developer.apple.com/programs/), official doc; free accounts
   get betas + on-device testing, not distribution).
7. **TCC / Screen Recording:** a stable Developer ID identity does fix the "re-approve on every
   update" problem *in principle*, because TCC records the app's **designated requirement** and checks
   later versions against it; TN3127 states outright that ad-hoc ("Sign to Run Locally") code has a DR
   "tied to that specific version of the code" so macOS cannot track identity across versions. Caveats:
   team-ID/bundle-ID changes break the DR, and switching between identities (e.g. Developer ID ↔
   local self-signed) invalidates existing grants.
8. **Tooling:** raw `codesign` + `xcrun notarytool` + `xcrun stapler` shell script is the most robust
   choice for a non-Xcode SwiftPM build. `altool` is dead for notarization (service stopped accepting
   it 2023-11-01). `fastlane` and `@electron/notarize`/`rcodesign` are third-party wrappers around the
   same Apple tools.
9. **Screen capture does not require any special hardened-runtime entitlement in Apple's
   documentation**, and Apple's own ScreenCaptureKit sample needs no entitlements at all — just TCC
   consent. App Sandbox is optional for direct distribution.
10. **Edge cases:** notarization is normally minutes but 98% within 15 minutes, capped at 75/day; every
    rebuild of the DMG changes its bytes and therefore requires re-notarization; stapling needs network
    access, but a stapled artifact then validates offline.

Bottom line: the only durable fix is Developer ID + notarization. Every alternative below changes
*where the user clicks*, not *whether they click*.

---

## 1. Diagnosing the dialog

### 1.1 The dialog the tester saw

Apple's own support article *Safely open apps on your Mac* contains a screenshot whose literal text is:

```
"Example App" Not Opened
Apple could not verify "Example App" is free of malware that may harm your Mac
or compromise your privacy.
[Done]   [Move to Trash]
```

Source: [Apple Support 102445](https://support.apple.com/en-us/102445) (official doc); I downloaded
and read the referenced image directly
(`https://cdsassets.apple.com/live/7WUAS350/images/macos/sequoia/macos-sequoia-app-not-opened-could-not-verify-free-from-malware.png`).
Note the asset path segment **`macos/sequoia/`**. The same article's section heading is still the
older wording ("Alert that Apple cannot check the app for malicious software"), which suggests Apple
swapped the screenshot text while keeping the heading.

The article's own explanation of that alert: *"If the app developer can't be verified and — in macOS
Catalina and later — the app hasn't been notarized by Apple, macOS can't verify that the app is free
of malware."* That is precisely the state of an ad-hoc-signed, unnotarized app carrying
`com.apple.quarantine`.

### 1.2 It is about the quarantine attribute

Gatekeeper only assesses **quarantined** items (things written by a downloading agent). Apple:

- *"all software in macOS is checked for known malicious content the first time it's opened,
  regardless of how it arrived on the Mac"* and *"By default, Gatekeeper helps ensure that all
  downloaded software has been signed by the App Store or signed by a registered developer and
  notarized by Apple."* — [Apple Platform Security, *Gatekeeper and runtime protection in macOS*](https://support.apple.com/guide/security/sec5599b66df/web), official doc
- *"When you install Mac apps, plug-ins, and installer packages from outside the App Store, macOS
  checks the Developer ID signature to verify that the software is from an identified developer and
  that it has not been altered. By default, macOS Catalina and later also requires software to be
  notarized"* — [Apple Support 102445](https://support.apple.com/en-us/102445), official doc

Practical consequence for this repo: the dialog fires because the DMG/ZIP were downloaded through a
browser (or anything that sets `com.apple.quarantine`), and the app inside has no Developer ID
signature and no ticket.

### 1.3 Which of the Gatekeeper dialogs is which

Apple's article documents the families of alert; I map them below. Apple does **not** publish an
authoritative table of "signature state → dialog string", so the "likely trigger" column is my
interpretation of Apple's prose plus the DTS forum material, not an Apple statement.

| Dialog text | Apple's description | Likely trigger |
|---|---|---|
| `"X" is an app downloaded from the Internet. Are you sure you want to open it?` | "The first time that you open a new app from an identified developer that you downloaded outside the App Store, your Mac asks if you're sure you want to open it." | Valid Developer ID signature; normal first-run confirmation |
| `"X" Not Opened — Apple could not verify "X" is free of malware…` | "Apple cannot check the app for malicious software"; "the app hasn't been notarized by Apple, macOS can't verify that the app is free of malware" | Quarantined code with a signature that is not a notarized Developer ID signature — **including ad-hoc** |
| `"X" cannot be opened because the developer cannot be verified` | "If the app developer can't be verified and … the app hasn't been notarized by Apple" | Identification/notarization failure (older, pre-Sequoia wording family) |
| `"X" will damage your computer` / `"X" is damaged and can't be opened` | "If macOS detects that software has been modified or damaged… The app might be broken or corrupted, or it might have been tampered with." | Signature invalid/tampered/revoked, or LaunchServices-level integrity failure |
| `"X" was not downloaded from the App Store` | Privacy & Security is set to "App Store" only | Policy setting, not signature |

Source for all quoted descriptions: [Apple Support 102445](https://support.apple.com/en-us/102445)
(official doc).

**Concrete difference for this bug:** a broken/absent signature produces the *damaged* family; a
present-but-unnotarized signature produces the *could not verify / free of malware* family. An ad-hoc
signature is a valid signature, so it lands in the second family — which is exactly what the tester
saw.

### 1.4 Which macOS version introduced this wording

- Apple's **2024-02-16** archived copy of the same article (pre-Sequoia) already has the section
  heading "Alert that Apple cannot check the app for malicious software" but pairs it with the older
  image set; the current article pairs it with a `macos/sequoia/…` asset showing the new text
  (Wayback Machine snapshot of `support.apple.com/en-us/102445`, via
  `http://web.archive.org/cdx/search/cdx?url=support.apple.com/en-us/102445`).
- Apple's Sequoia-era announcement of the related behaviour change is dated **6 August 2024**:
  *"In macOS Sequoia, users will no longer be able to Control-click to override Gatekeeper when
  opening software that isn't signed correctly or notarized."* —
  [Apple Developer News, *Updates to runtime protection in macOS Sequoia*](https://developer.apple.com/news/?id=saqachfa) (official Apple announcement).
- Public reports of this exact string begin with macOS 15 Sequoia (e.g. Apple Discussions threads
  from November 2024 onward: `discussions.apple.com/thread/255852595`).

**Not established:** Apple has never published a per-release changelog of Gatekeeper dialog strings.
The evidence above is strong that the *"could not verify … is free of malware"* wording is
Sequoia-specific (and persisted into macOS 26/27 in Apple's current article), but there is no Apple
statement that says "macOS 15 introduced this string". Flagged in the final section.

---

## 2. Minimum fix that removes the dialog entirely

### 2.1 Certificate: Developer ID Application is mandatory

Apple, *Notarizing macOS software before distribution* (official doc,
<https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution>):

> "Use a 'Developer ID' application, kernel extension, system extension, or installer certificate for
> your code-signing signature. (Don't use a Mac Distribution, ad hoc, Apple Developer, or local
> development certificate.)"

And, *Resolving common notarization issues* (official doc,
<https://developer.apple.com/documentation/security/resolving-common-notarization-issues>):

> "You can only notarize apps that you sign with a Developer ID certificate. If you use any other
> certificate — like a Mac App Distribution certificate, or a self-signed certificate — notarization
> fails."

Signing an **app or DMG** uses `Developer ID Application`; signing a **flat installer package** uses
`Developer ID Installer`. Do not mix them.

### 2.2 The full requirement list for notarization

From *Notarizing macOS software before distribution* (official doc):

- valid code signature on every executable;
- Developer ID certificate (see above);
- **Hardened Runtime enabled** for the app and CLI targets;
- **secure timestamp** in the signature;
- no `com.apple.security.get-task-allow` entitlement (value must not be true);
- link against the macOS 10.9 or later SDK;
- entitlements must be well-formed, ASCII-encoded XML plists (no BOM).

The timestamp point is worth spelling out because it bites command-line builds: *"By default, Xcode
doesn't include a secure timestamp as part of the app's code signature during the build process …
be sure to add a secure timestamp by adding the `-timestamp` option"* (Resolving common notarization
issues, official doc). `codesign --timestamp` uses an Apple timestamp server by default (man page).

Notarization becomes mandatory for distribution on modern macOS: *"Beginning in macOS 10.14.5,
software signed with a new Developer ID certificate … must be notarized to run. Beginning in macOS
10.15, all software built after June 1, 2019, and distributed with Developer ID must be notarized."*
(Notarizing macOS software before distribution, official doc.)

### 2.3 Signing command

`codesign` man page (man page) documents both flags:

- `--options runtime` — *"On macOS versions >= 10.14.0, opts signed processes into a hardened runtime
  environment … These restrictions can be selectively relaxed via entitlements."*
- `--timestamp [=URL]` — requests a timestamp authority; default is an Apple server.

So the app signature is, minimally:

```sh
codesign --force --timestamp --options runtime \
  --sign "Developer ID Application: <Name> (<TEAMID>)" \
  "ScreenCaptureAll.app"
```

Notes:

- Apple's packaging doc says to sign **inside-out**: sign nested code first, then the app bundle.
  (Quinn's guidance is to avoid `--deep` for signing — the man page retains it but Apple DTS
  explicitly recommends against it: [forum thread 665901](https://developer.apple.com/forums/thread/665901), forum, Apple DTS.)
- Signing a `SwiftPM`-produced bundle is fine; the constraint is not Xcode, it is using the
  `codesign`/`notarytool`/`stapler` tools with a Developer ID identity
  ([Xcode: *Packaging Mac software for distribution*](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution), official doc — it explicitly addresses products built with third-party tools and command-line signing).

### 2.4 What must be notarized and stapled

Apple, *Packaging Mac software for distribution* (official doc):

> "If you distribute your product using nested containers, only notarize the outermost container. For
> example, if you have an app inside an installer package on a disk image, sign the app, sign the
> installer package, and sign the disk image, but only notarize the disk image."
>
> "Once you've notarized your product, staple the resulting ticket to the file you intend to
> distribute. … The other common container formats, installer packages and disk images, support
> stapling directly."

But a DMG ticket is only *ingested* when Gatekeeper evaluates the DMG (i.e. the user opens it in
Finder). Quinn (Apple DTS):

> "For Gatekeeper to ingest your ticket it must evaluate your product. When you run `open`, it opens
> the disk image using `NSWorkspace` which does a basic Gatekeeper check on it, which triggers that
> ingestion. This doesn't happen when you mount it with `hdiutil`."
> — [forum thread 741219](https://developer.apple.com/forums/thread/741219) (forum, Apple DTS)

And the canonical statement of the rule:

> "Sign everything, from the inside out. Notarise the outermost container. Staple the outermost
> container, assuming it supports stapling." — [forum thread 125512](https://developer.apple.com/forums/thread/125512) (forum, Apple DTS)

The ZIP case is special (Apple, *Customizing the notarization workflow*, official doc):

> "While you can notarize a ZIP archive, you can't staple to it directly. Instead, run `stapler`
> against each item that you added to the archive. Then create a new ZIP file containing the stapled
> items for distribution." Also: "Although tickets are created for standalone binaries, it's not
> currently possible to staple tickets to them."

**Recommended sequence for this repo** (two-pass; DMG and ZIP both valid offline):

1. Build, sign the app inside-out (`--options runtime --timestamp`).
2. Zip the app and `notarytool submit --wait` that zip. (notarytool accepts UDIF DMGs, signed flat
   installers, and **zip files** only — man page.)
3. `xcrun stapler staple ScreenCaptureAll.app` (staple the app so the ZIP and `hdiutil` paths work
   offline).
4. Produce the shippable ZIP from the **stapled** app.
5. Build the DMG from the **stapled** app.
6. Sign the DMG with the Developer ID Application identity.
7. `notarytool submit --wait ScreenCaptureAll.dmg`, then `xcrun stapler staple ScreenCaptureAll.dmg`.

A one-pass variant (skip steps 2–4, notarize only the DMG) is what Apple's doc describes as
sufficient for the ordinary Finder flow; the two-pass variant is what makes the non-Finder paths and
the ZIP offline-safe. Both are defensible; the two-pass one costs a second notarization.

### 2.5 Does the DMG's own signature matter?

No — not for the dialog. Quinn (Apple DTS):

> "The notary service does not require that your disk image be signed. If the disk image is signed
> then it'll include the image itself in the ticket (along with all the image's content). If not, the
> ticket is built just from the image's content. Having said that, I do recommend that you sign your
> disk image."
> — [forum thread 675354](https://developer.apple.com/forums/thread/675354) (forum, Apple DTS)

The `stapler` man page agrees on the mechanics: stapling accepts *"UDIF disk images, signed 'flat'
installer packages, and certain code-signed executable bundles such as '.app'"*, and it only treats
an **unsigned flat installer package or unsigned executable bundle** as an error. An unsigned DMG is
not called out as an error.

Apple's packaging doc nonetheless instructs signing the DMG with the Developer ID Application
identity, and requires third-party DMG tooling to produce images signed that way and in UDZO
("UDIF-format read-only zip-compressed") format — which the repo already uses.

### 2.6 Does ad-hoc + hardened runtime help?

No, for distribution:

- Notarization cannot use an ad-hoc certificate (quoted above).
- Gatekeeper wants Developer ID + notarization (quoted in §1.2).
- Ad-hoc + `--options runtime` changes only local runtime behaviour (library validation, JIT
  restrictions, etc. — `codesign` man page), and it changes the TCC story not at all (§4).

Ad-hoc code *is* still runnable if the quarantine attribute is absent, which is why local builds and
`swift run` work — and why the repo's diagnostic `.app` (self-signed, local) is usable.

### 2.7 Entitlements

- Hardened runtime requires **no** entitlements by itself; entitlements only relax individual runtime
  protections or grant resource access. *"To upload a macOS app to be notarized, you must enable the
  Hardened Runtime capability"* — [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime) (official doc).
- The one entitlement that must be **absent** is `com.apple.security.get-task-allow` (Notarizing… doc,
  and Resolving common notarization issues, official docs).
- Entitlement files must be ASCII XML, no BOM (Resolving common notarization issues, official doc).
- Xcode's convention — *"it includes an entitlement only if the value is true. If you're manually
  signing code, follow this convention"* (Hardened Runtime, official doc) — matters if you hand-write
  an entitlements plist.
- Screen-capture-specific entitlements: see §6.

---

## 3. Alternatives to paying for an Apple Developer account

Short version: **none of them remove the dialog.** They change where the user has to click, and in
one case (Homebrew) the ecosystem is actively closing the loophole.

| Option | Removes the dialog? | What it actually does | Cost / risk |
|---|---|---|---|
| Ad-hoc signing (today) | No | Signature is valid but not Developer ID, so Gatekeeper refuses; also TCC identity churns per build (§4) | Free; every user hits the dialog + Screen Recording re-approval |
| Self-signed certificate in login keychain | No | Gatekeeper/notarization still refuse it (Resolving common notarization issues, official doc). It **does** give a stable code signing identity, which stabilises the TCC designated requirement for *local* builds — the repo already does this for the diagnostic app | Free; zero Gatekeeper benefit; identity differs from the shipped Developer ID build |
| Instruct users to strip quarantine (`xattr -d com.apple.quarantine`) | Works, but is a user-side security bypass | Removes the trigger entirely, because Gatekeeper only assesses quarantined items | Free. Teaches users to disable a security control for your app; needs a Terminal step; must be re-done per download/update if quarantine is re-applied |
| Homebrew cask | No longer viable | Official casks must pass Gatekeeper, and Homebrew has deprecated `--no-quarantine` and unsigned casks | Homebrew's stated policy: unsigned/unnotarized casks are deprecated and removed from the official tap by **September 2026** |
| "Open Anyway" in System Settings | Not really — it is a per-app override | User blocks, then goes to Privacy & Security → Open Anyway, then re-confirms | Free; still a scary dialog first, per app, per first launch; needs an admin |
| `spctl --global-disable` / "Allow apps from Anywhere" | Yes, globally | Reveals the "from anywhere" option in Privacy & Security; disables assessment system-wide | Free; turns off Gatekeeper for everything |
| Free Apple account notarization | No such thing | Free accounts get betas + on-device testing; **distribution via Developer ID requires membership** | $99/yr is the only path |

### 3.1 macOS 15 (Sequoia) removed the Control-click override

Apple explicitly:

> "In macOS Sequoia, users will no longer be able to Control-click to override Gatekeeper when
> opening software that isn't signed correctly or notarized. They'll need to visit System Settings >
> Privacy & Security to review security information for software before allowing it to run."
> — [Apple Developer News, *Updates to runtime protection in macOS Sequoia*, 6 Aug 2024](https://developer.apple.com/news/?id=saqachfa) (official Apple announcement)

This is the key change for a $0 workaround: right-click → Open no longer exists. The remaining
override is a trip to System Settings, which Apple documents in 102445 with the "Open Anyway" button
(official doc, article last published 27 May 2026, so this path still exists on the OS versions the
article covers).

### 3.2 What changed with `spctl` on macOS 15+

The current `spctl(8)` man page (man page, Apple):

- `--global-disable` — *"Reveal the option to allow applications downloaded from anywhere in the
  Privacy & Security settings pane."*
- `--global-enable` — re-enable assessment.
- Under **DEPRECATED OPTIONS**: *"As of MacOS 15.0, operations that modify the rule database or the
  global state of the assessment subsystem will no longer be supported."* (`--add`, `--disable`, …)

So the old per-rule `spctl --add` trick is gone as of macOS 15; only the global toggle (and
configuration profiles) remain.

### 3.3 Homebrew route

Homebrew's own docs and issue tracker (vendor doc):

- FAQ/Cask policy: *"Official macOS casks must pass Homebrew's Gatekeeper checks without requiring
  users to bypass them."*
- [Homebrew/brew#20755](https://github.com/Homebrew/brew/issues/20755): `--no-quarantine` is being
  removed precisely because *"it intentionally bypasses macOS security mechanisms"*; casks that fail
  Gatekeeper are **deprecated and removed from the official tap by 1 September 2026**.
- Cask upgrade logic now verifies the new app satisfies the old app's **designated requirement**
  before inheriting the user's approval — the same DR concept TCC uses (Homebrew docs for
  `Cask::Quarantine` / `Cask::Upgrade`).

Practical read: as of the current Homebrew (6.x), the cask route no longer provides quarantine
stripping for you, and official casks will require notarization anyway. A *formula* that builds from
source sidesteps quarantine, but that is source installation, not an app download.

### 3.4 Is there any free notarization path?

Not found, and Apple's own material contradicts it:

- Notarization requires a Developer ID certificate (Resolving common notarization issues, official doc).
- Developer ID is described in Apple's program material as part of paid membership: *"You can even
  choose to distribute your Mac apps outside the Mac App Store using your Developer ID certificate and
  Apple's notarization process"* listed under the **$99 annual membership** benefits, while the free
  tier is listed as betas, on-device testing, forums and Feedback Assistant —
  [Apple Developer Program](https://developer.apple.com/programs/) (official doc).

The Apple Developer Enterprise Program is $299/year and is for internal distribution, not a cheaper
route.

---

## 4. TCC / Screen Recording identity stability

### 4.1 How macOS establishes "same app" for privacy permissions

TN3127, *Inside Code Signing: Requirements* (tech note, Apple) is explicit that this is the
**designated requirement (DR)**, not the bundle ID and not the cdhash alone:

> "A few days later your app's software update mechanism runs and replaces version 1.2 with version
> 1.3. … How can macOS tell that version 1.3 of your app is the 'same code' as version 1.2? macOS
> solves this problem by recording your app's DR in its database of apps authorized to access the
> microphone. Each time your app tries to access the microphone, macOS checks that this version of the
> app satisfies the original DR."

The sentence that answers this repo's problem directly:

> "**Unsigned code has no DR. Ad hoc signed code, called Sign to Run Locally by Xcode, has a DR but
> it's tied to that specific version of the code.** In both cases macOS can't reliably track the
> identity of the code. You often see this problem when you create a simple test project in Xcode and
> don't bother to enable code signing. If the app accesses the microphone, macOS prompts you to
> authorize that access. If you tweak the code and run it again, macOS repeats that prompt. Without a
> DR, macOS can't track this authorization across versions of your app."
> — [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) (tech note)

TN3126, *Inside Code Signing: Hashes*, defines cdhash (*"Hashing a code directory results in a code
directory hash, or cdhash"*) and states *"A notarized ticket is a set of cdhash values"* (tech note).
So the cdhash is the per-build integrity value; the DR is the cross-version identity. A DR may be
satisfied by a cdhash (that is what an ad-hoc DR reduces to), which is exactly why ad-hoc builds are
"new apps" to TCC.

Screen Recording is one of the TCC-protected macOS classes — Apple lists it explicitly: *"macOS: Input
monitoring …, Prompt, Screen recording (for example, static screen shots and video) …"* —
[Apple Platform Security, *Protecting app access to user data*](https://support.apple.com/guide/security/secc01781f46/web) (official doc).

### 4.2 Does a stable Developer ID signature fix re-approval?

Yes, in principle, and for the reason TN3127 gives: with a Developer ID signature the app has a DR
that is *not* tied to a single build. TN3127's Developer ID DR example is built from
`anchor apple generic`, the Developer ID OIDs, the Team ID (OU field) and the code signing identifier
(bundle ID) — none of which change when you rebuild version 1.3.

This is corroborated at the practical level by an Apple Developer Forums thread about ScreenCaptureKit
on macOS 26: the reporter says the permission was reset after every build under ad-hoc signing, and
that switching the Debug identity to a stable certificate fixed it; the thread also contains a
one-line reply agreeing that, with ad-hoc signing, "the system treats each build as a 'new' app".
— [forum thread 819406](https://developer.apple.com/forums/thread/819406) (forum).

**Caveat on that citation:** the Apple forums serve content client-side behind bot protection, so I
could not fetch the page directly and confirm the identity of the responder; the thread title and
excerpt come from a search-index rendering of the forum page. Treat the *mechanism* as sourced from
TN3127 (solid) and the forum thread as corroboration only.

### 4.3 Known caveats (all sourced from TN3127 unless noted)

- **Changing Team ID or code signing identifier changes the DR.** TN3127's Developer ID DR embeds both.
- **Xcode applies *custom* DRs** for mutual Mac App Store ↔ Developer ID compatibility; if you sign
  with plain `codesign`, you get the *default* DR, which is not mutually compatible across channels
  (TN3127: *"Mac App Store and Developer ID variants of your app aren't mutually compatible. Xcode
  avoids this limitation by signing code with custom DRs"*).
- **Switching signing identity between releases invalidates grants.** A Developer-ID-signed 1.0 and a
  locally-signed 1.1 do not satisfy each other's DRs, so TCC sees two different apps. This affects the
  repo directly: the diagnostic `.app` (self-signed "…Diagnostics Development") and the shipped app
  will never share a TCC grant.
- **Apple Development ≠ Developer ID for DR purposes** (TN3127 gives a separate, incompatible DR for
  Apple Development), so a "switch Debug to Apple Development" fix stabilises *dev* builds but does not
  mean the shipped build shares that grant.
- **UNCONFIRMED:** whether TCC stores only `csreq` (DR) or also a cdhash and can fail when both are
  present. TN3127 describes the DR mechanism; third-party bug reports assert a cdhash component too,
  but I found no Apple source stating that.

---

## 5. Tooling for a SwiftPM (non-Xcode) app

| Tool | Apple-supported for notarization? | What it does | Credentials | Notes |
|---|---|---|---|---|
| `codesign` + `xcrun notarytool` + `xcrun stapler` (shell) | **Yes** — the documented path | Sign, submit, staple | App Store Connect API key (`.p8` + Key ID + Issuer ID) **or** Apple ID + app-specific password + Team ID, or a stored keychain profile | Nothing extra to install beyond Xcode 13+/Command Line Tools; works with any build system. **Recommended.** |
| `xcrun altool` | **No — removed for notarization** | Legacy notarization + App Store upload | same family | *"Apple has deprecated `altool` for the purposes of notarization and announced that it will stop working for notarization on 2023-11-01"* (TN3147, tech note). Apple Developer News: from 1 Nov 2023 the notary service *"will no longer accept uploads from `altool` or Xcode 13 or earlier"* ([Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/?id=11012023a), official). Corroborated locally: the shipped Command Line Tools no longer provide `altool`, only `notarytool`. Still valid for App Store uploads (TN3147). |
| `fastlane` (`notarize`, `match`, `sigh`) | Third-party | Wraps `notarytool`; `match` manages certs | API key or Apple ID + app-specific password | [fastlane `notarize`](https://docs.fastlane.tools/actions/notarize/) (vendor doc): params include `api_key_path`/`api_key`, `username`, `skip_stapling`. Useful if you already use fastlane; adds a Ruby dependency for a shell-script problem. |
| `@electron/notarize` | Third-party | Wraps `notarytool`; zips with `ditto`, stapling via `notarytool`+`stapler` | API key or Apple ID + ASP, or keychain profile | [electron/notarize](https://github.com/electron/notarize) (vendor doc). Its v3.1.2 release notes record *"The Legacy strategy for Apple's sunset `altool` has now been removed"*. Node-only, so not a natural fit here. |
| `rcodesign` / `apple-codesign` (Rust) | Third-party | Sign, notarize, staple `.app`, `.pkg`, `.dmg` — including from Linux/Windows | App Store Connect API key JSON | [indygreg/apple-platform-rs](https://github.com/indygreg/apple-platform-rs/tree/main/apple-codesign) (vendor doc). Only worth it if you ever need to build/sign off macOS. |
| Xcode Cloud / "cloud signing" | Yes for Xcode | Managed identities | App Store Connect | Not usable here: Quinn notes cloud signing *"is only supported in Xcode (and `xcodebuild`). It's not directly supported by `codesign`"* ([forum 799215](https://developer.apple.com/forums/thread/799215), forum, Apple DTS). |
| Notary REST API | Yes | Direct HTTP upload | API key | Documented, but `notarytool` is explicitly the easier path (Notarizing… doc). |

### 5.1 Credentials and CI wiring

`notarytool` authentication (man page + TN3147, tech note):

- **App Store Connect API key:** `-k/--key <AuthKey_XXXX.p8>` `-d/--key-id <KEYID>` `[-i/--issuer
  <ISSUER-UUID>]`. The issuer ID is **required for Team keys** and **must be omitted for Individual
  keys** (omitting/passing it wrongly yields HTTP 401). No Apple ID needed.
- **Apple ID + app-specific password:** `--apple-id <id> --team-id <TEAMID>` and either
  `--password <asp>` or an interactive prompt. Requires 2FA-enabled account with an app-specific
  password.
- **Keychain profile:** `notarytool store-credentials <name> …` then `-p <name>` everywhere. Can be
  written to a file-based keychain with `--keychain <path>` (useful in CI) rather than the data
  protection keychain.

GitHub Actions certificate handling (GitHub's own documentation, vendor doc): create an ephemeral
keychain, import the base64-encoded `.p12`, allow the tool to use it without a UI prompt, and point the
user search list at it:

```sh
security create-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security unlock-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
security import $CERT_PATH -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k $KEYCHAIN_PATH
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
security list-keychain -d user -s $KEYCHAIN_PATH
```

([Installing an Apple certificate on macOS runners](https://docs.github.com/en/actions/deployment/deploying-xcode-applications/installing-an-apple-certificate-on-macos-runners-for-xcode-development),
vendor doc — GitHub documents this for Xcode, but the keychain steps are identical for `codesign`.)
For a GitHub-hosted runner the keychain dies with the VM; for self-hosted runners GitHub tells you to
delete the keychain in a cleanup step.

Practical CI shape for this repo: secrets `DEVELOPER_ID_P12` (base64), `P12_PASSWORD`,
`KEYCHAIN_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (base64 of `AuthKey_*.p8`).
`notarytool` can take the `.p8` path directly, so no notarytool keychain profile is strictly needed.

**Recommendation:** stay with the raw `codesign` + `notarytool` + `stapler` shell script. It is what
Apple documents, it is what the repo's `Scripts/package_app.sh` already is, and it avoids adding a Ruby
or Node toolchain to the release job. `fastlane` is the reasonable second choice if certificate
management (`match`) is wanted; I would not claim either is objectively "best" — the deciding factor is
whether you want a dependency to manage certs for you.

---

## 6. Notarization gotchas for a screen-capture app

### 6.1 Does TCC / Screen Recording interact with notarization or hardened runtime?

I found **no** Apple statement that notarization or hardened runtime affects Screen Recording TCC.
The two systems are independent: Gatekeeper decides whether the app may launch at all; TCC decides
whether a running app may capture the screen. If Gatekeeper blocks the launch, TCC never comes into
play; if the app launches, TCC prompts normally regardless of notarization status.

The practical interaction is indirect but real: **ad-hoc signing makes TCC treat each build as a new
app** (§4), and **notarization requires Developer ID signing**, so adopting notarization also fixes the
TCC churn.

### 6.2 Entitlements needed for screen capture on macOS 26

Nothing specific is documented. Evidence:

- Apple's ScreenCaptureKit sample *Capturing screen content in macOS* (official doc,
  <https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos>)
  says only: *"The first time you run this sample, the system prompts you to grant the app Screen
  Recording permission. After you grant permission, you need to restart the app to enable capture."*
  It does not mention any entitlement.
- The Hardened Runtime entitlement list (official doc) contains `com.apple.security.device.audio-input`
  ("record audio using the built-in microphone and access audio input using Core Audio") and
  `com.apple.security.device.camera`, but **no screen-capture entitlement**.
- Apple's platform-security page classifies Screen recording purely as a TCC/privacy class, not as an
  entitlement-gated capability (official doc).

Therefore: no entitlement is *required* for screen capture. If this app ever records **microphone**
audio, `com.apple.security.device.audio-input` is the relevant hardened-runtime resource-access
entitlement (official doc). Whether ScreenCaptureKit **system-audio** capture requires it is
**UNCONFIRMED** — I found no Apple statement either way.

### 6.3 Is App Sandbox required?

No. App Sandbox (`com.apple.security.app-sandbox`) is mandatory for Mac App Store distribution;
direct Developer ID distribution does not require it. Apple's *App Sandbox* doc describes it as the
mechanism for App Store apps, and the hardened-runtime doc notes that Apple requires sandboxing for
App Store apps — *"All apps from the App Store are sandboxed"* (Apple Platform Security, official doc).
The repo's app is not sandboxed today and does not need to become sandboxed to be notarized.

Note also that sandboxing a screen-capture app has its own cost: the older `screencapture` CLI path
needed a `com.apple.security.temporary-exception.mach-register.global-name` exception for interactive
capture (Apple's archived
[App Sandbox Temporary Exception Entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html),
official/archived doc). Avoiding the sandbox avoids that class of problem.

### 6.4 `CGPreflightScreenCaptureAccess`

Its documentation page did not render usable content through the docs API during this research
(the `developer.apple.com/tutorials/data/…` JSON returned no content sections for
`coregraphics/cgpreflightscreencaptureaccess()`). I therefore make **no claim** about entitlement
interaction with these functions. What is documented at the platform level is that Screen Recording is
a TCC class and that the system prompts on first use (see above). Treat any claim that these functions
are affected by entitlements as unverified.

### 6.5 Notarization-specific gotchas that will hit this build

- The notary service accepts **only** UDIF disk images, signed flat installer packages, and ZIP files —
  a bare `.app` cannot be submitted (notarytool man page; *Customizing the notarization workflow*,
  official doc: *"you can't upload the `.app` bundle directly to the notary service, you'll need to
  create a compressed archive"*).
- `com.apple.security.get-task-allow` must not be present (Notarizing…, official doc).
- Entitlements must be ASCII XML with no BOM (Resolving common notarization issues, official doc).
- Universal binaries are fine and expected; TN3126 notes each architecture is signed independently
  with its own code directory, so the ticket contains one cdhash **per architecture** — this is why a
  universal build's ticket is larger and why arch-specific mistakes show up as "missing from ticket"
  (TN3126, tech note).

---

## 7. Edge cases worth flagging

**Turnaround & CI timeouts.** *"Notarization completes for most software within 5 minutes, and for 98
percent of software within 15 minutes. However, notarization can take longer under certain
conditions."* Apple lists the causes (many files, non-executable content inside signed locations,
heavily compressed images, huge data files) and a hard **limit of 75 notarizations per day**
(*Customizing the notarization workflow*, official doc). `notarytool submit --wait --timeout <dur>`
exists precisely so a CI job cannot hang indefinitely; the submission continues server-side after the
timeout (man page).

**`stapler` needs the network.** *"stapler requires internet access to retrieve tickets when stapling
or validating"* (stapler man page). The *purpose* of stapling is the opposite: once stapled, *"This
ensures that Gatekeeper can find the ticket even when a network connection isn't available"*
(*Customizing the notarization workflow*, official doc). So: stapling needs network, validation after
stapling does not.

**Stapling order is binding.** *"Stapling does not invalidate the code signature and must be run after
an executable or archive has been code-signed and notarized with Developer ID. Code-signing a
supported file format invalidates any stapled tickets, so `stapler staple` must be run again if this
occurs."* (stapler man page). Re-signing after stapling silently loses the offline ticket.

**Re-notarization on rebuild.** Tickets identify code by **cdhash** (TN3126; *The Pros and Cons of
Stapling*, forum, Apple DTS). Any change to the app — including re-signing, editing resources, or
re-stapling if that altered bytes — changes the cdhash. Rebuilding the DMG certainly changes the DMG's
content, so **a rebuilt DMG must be re-notarized and re-stapled**; you cannot reuse the previous
ticket. Correspondingly, do not create the DMG before signing the app, and do not touch the DMG after
stapling.

**Already-published releases.** Apple recommends notarizing *existing* releases too:
*"Apple recommends that you notarize all of the software that you've distributed, including older
releases… Submit everything you've previously released, as well as your most recent version"*
(Notarizing macOS software before distribution, official doc). For this repo, that means the already-
published ad-hoc DMGs stay broken for users unless you either re-notarize them (they cannot be —
notarization requires a Developer ID signature, so they must be re-signed and rebuilt) or replace them.
Practically: publish a new notarized release and point users at it; consider a note in the release
body for the old tags.

**Parallelizing / caching.** Apple documents no caching and no batch API for `notarytool submit` —
submissions are per-file, and the daily cap is 75 (above). The only "cache" is on the client side:
`.p8` API keys and (optionally) a stored keychain profile. Because the ticket is keyed by cdhash,
submitting a byte-identical file again is wasted work, so in CI gate the notarization step on "did the
signed artifact change" rather than running it unconditionally. Notary logs *"might contain warnings
that you can fix prior to your next submission"*, so always fetch the log even on success (Customizing
the notarization workflow, official doc).

**Also worth knowing:** if you ever ship the app *inside* the DMG such that the ticket must be ingested
without Finder (e.g. an auto-updater that `hdiutil attach`es the image), the DMG ticket is **not**
ingested — staple the app itself as well (forum thread 741219, Apple DTS).

---

## Open Questions / Not established by sources

1. **Exact macOS version that introduced the `could not verify … is free of malware` string.** Apple
   never published a dialog-string changelog. Evidence points at macOS 15 Sequoia (Apple's asset path,
   the Sequoia-era announcement of the related override change, user reports from Nov 2024), but there
   is no Apple statement.
2. **Authoritative mapping from signature state → dialog.** Apple documents the *families* of alerts
   and says "you could see a similar message that isn't displayed here"; there is no Apple table
   telling you that ad-hoc + quarantined yields this specific string. My §1.3 mapping is inference.
3. **Does `stapler staple My.app` succeed when the only ticket came from notarizing the enclosing
   DMG?** Mechanically yes (the ticket is a set of cdhashes and the app's cdhashes are in it), but I
   found no Apple statement confirming `stapler` satisfies its per-item lookup from a
   container-derived ticket. The two-pass order I recommend avoids depending on this.
4. **Does stapling an `.app` change its cdhash?** The stapler man page only says stapling does not
   invalidate the signature. If stapling did change the app's cdhash, stapling the app *before* building
   the DMG would invalidate the app's entry in the DMG ticket. The recommended order (staple app, then
   build/sign/notarize DMG) sidesteps the question; I could not source a definitive answer.
5. **Whether TCC stores a cdhash in addition to the designated requirement.** TN3127 describes DR-based
   checking; third-party reports assert a cdhash component. No Apple source found.
6. **Whether ScreenCaptureKit system-audio capture needs `com.apple.security.device.audio-input`** under
   the hardened runtime. Apple documents the entitlement only for microphone/Core Audio input.
7. **`CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess` behaviour and any entitlement
   interaction.** Their documentation pages did not return content during this research; no claims made.
8. **Responder identity on Apple Developer Forums thread 819406.** The forums are bot-protected and
   could not be fetched directly; the thread is cited as corroboration, not as an Apple engineer
   statement.
9. **Whether the "damaged" dialog ever fires for a *valid* ad-hoc signature with quarantine.** Apple
   describes "damaged" as modified/tampered; there are third-party reports of a Sequoia Gatekeeper bug
   wrongly reporting notarized apps as damaged, which I could not confirm from Apple.
