# Security policy

MacToys reads your clipboard, takes screenshots, and — if you grant it —
observes keystrokes. That is a lot of trust for a menu-bar app, so this page
says plainly what it does with that access and how to tell me when something is
wrong with it.

## Reporting

Email **singhpiyush1806@gmail.com**. Please do not open a public issue for
anything that could expose other people's data until it is fixed.

I am one person doing this in my spare time, so I will not promise a response
time I cannot keep. I will read it, reply when I have actually looked, and
credit you in the release notes unless you would rather I did not.

## Supported versions

The latest release. There are no long-term branches to back-port to.

## What the app actually does

Worth stating, because it is what most reports will be about:

- **There is no network code in this repository.** Nothing is uploaded, and
  there is no telemetry, crash reporting, or update check. If you find any code
  that opens a socket, that is a serious bug and I want to hear about it.
- **Clipboard history is a plain file** at
  `~/Library/Application Support/MacToys/`, readable by your user account and
  not encrypted. Turning off *Remember history* in Settings keeps it in memory
  only. It is not protected against someone who already has your account.
- **Password managers are skipped.** Pasteboards marked
  `org.nspasteboard.ConcealedType` are never recorded. A password manager that
  fails to set that marker, or a case where the check fails, is a real bug.
- **Screenshots are saved to disk** when that setting is on, in your screenshots
  folder, exactly where any screenshot would go.

## In scope

- Recording a pasteboard that should have been skipped as concealed
- Clipboard data reaching anywhere other than that one file
- Any network traffic at all
- Excluded apps having their clipboard recorded anyway
- Getting MacToys to run code it should not, or use its permissions on behalf of
  something else
- Anything in the release or signing pipeline that would let a third party ship
  something as MacToys

## Not vulnerabilities

- **The "developer cannot be verified" warning.** Releases are signed, but with
  a self-signed certificate rather than a $99/year Apple Developer ID. This is
  documented and deliberate.
- **Clipboard history being readable by your own user account.** That is what it
  is; turn off *Remember history* if you do not want it on disk.
- **Needing Accessibility or Screen Recording.** Window snapping, the remapped
  keys, snip and OCR cannot work without them. macOS allows no way around that,
  and the rest of the app works without granting either.
