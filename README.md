# dText

A native macOS text expander built with SwiftUI and AppKit. Create an abbreviation once and insert your text in other applications by typing it.

## Run

1. Open `dText.xcodeproj` in Xcode 27 or newer.
2. Select the **dText** scheme and **My Mac**, choose your signing team if needed, then run.
3. Click **Enable text expansion** and enable the running dText copy in **System Settings → Privacy & Security → Device Control and Data Access** (called **Accessibility** before macOS 27). Permission status refreshes automatically, including when returning from System Settings.
4. In TextEdit or another editor, type `;thanks`. It should become “Thanks so much for your help. I really appreciate it!”

The deployment target is macOS 14. The project has no third-party dependencies. The app is intentionally outside App Sandbox: global keyboard event interception and insertion require Accessibility access. Developer ID signing and notarization are separate distribution steps.

The **Playground** works without system permissions. Closing the last window removes dText from the Dock while keeping text expansion and the menu bar active. Choose **Open dText** from the menu bar to reopen the library and restore its Dock icon; use **Quit dText** to stop it.

### Permission enabled, but shortcuts do not work

macOS authorizes signed applications, not just the name `dText.app`. A locally signed packaged build and an Apple Development-signed Xcode build can have the same bundle identifier but different signing requirements. An enabled entry for the old build does not establish that the running build has access.

1. In dText Settings, click **Show running app in Finder**. When running from Xcode this is the app under `DerivedData/.../Build/Products/Debug/`.
2. In the macOS permission list, remove the existing dText entry, add that exact app copy, and enable it.
3. Stop and run dText again in Xcode. Check **Keyboard control: Allowed for this copy** and **Keyboard listener: Connected** in dText Settings, then test a currently configured abbreviation in TextEdit.

Use consistent Apple Development signing for regular debug runs and avoid alternating with an ad-hoc-signed build under the same bundle identifier. Permission diagnostics are written to the Xcode console only when the permission state changes; typed content is never logged. The app neither resets macOS privacy settings nor grants itself permission.

Enable **Settings → Startup → Open dText at login** to launch it automatically when you sign in. This uses macOS Login Items, and the setting reflects changes made in System Settings. If macOS requires approval, follow the **Approve in Login Items…** button. Keep the app in a stable location, such as `/Applications`, before enabling login startup.

## Included

- Create, edit, duplicate, delete, enable, and favorite snippets.
- Named sets with colors, icons, prefixes, suffixes, and per-application inclusion/exclusion rules.
- Global application exclusions and pause/resume.
- Immediate, word-separator, and regular-expression triggers.
- Case-sensitive, case-insensitive, and adaptive capitalization; optional word boundaries.
- Plain text, rich text with native font controls, HTML, and image expansions.
- Date/time formats, clipboard content, cursor placement, input fields, dropdowns, UUIDs, nested snippets, and regex captures.
- Quick Search with **Shift–Command–Space**, arrow-key navigation, and Return to insert into the previous application.
- Menu bar favorites, optional expansion sound, clipboard restoration, and launch at login.
- Search across names, abbreviations, content, and notes; recent and most-used sorting.
- Usage counts, saved characters, and estimated saved typing time.
- Local JSON persistence with atomic writes and one previous-file backup.
- JSON library/set import and export; tab-separated text import.
- Starter examples, an interactive playground, and an in-app guide.
- Light and dark appearance and a native app icon.

## Template syntax

Use variables in **plain text** and **HTML** expansions:

| Token | Result |
| --- | --- |
| `{{date}}` | Current date |
| `{{date:yyyy-MM-dd}}` | Date with a DateFormatter format |
| `{{time:HH:mm}}` | Current time |
| `{{clipboard}}` | Clipboard text, inserted literally |
| `{{cursor}}` | Final cursor position in a plain text expansion |
| `{{field:Name}}` | Prompt for a value |
| `{{choice:Size\|Small\|Large}}` | Prompt with a dropdown |
| `{{snippet:;sig}}` | Include a snippet by its own abbreviation, without its set prefix/suffix |
| `{{capture:1}}` | First regex capture; `0` is the whole match |
| `{{uuid}}` | New UUID |
| `{{tab}}`, `{{return}}` | Literal tab/newline characters |

For example, `Hi {{field:Name}},\n\nThanks for your message.\n{{cursor}}` asks for a name and leaves the cursor at the end. Fields are collected once in appearance order. Nested snippets reject recursion. Clipboard/field values are never evaluated again as templates.

Regex triggers match the end of the typed buffer (256 characters). Longest matches win; library order breaks ties. Expensive regex searches have a small execution budget. Prefer an explicit terminator, such as `;issue(\d+);`, because an immediate regex can match before the user finishes typing a longer value.

## Storage and import

The library is stored in `~/Library/Application Support/dText/library.json`. The last saved version is also kept as `library.json.backup`. Export a JSON file for portable backups or sharing. Imports append new sets and remap IDs; they do not replace existing content or import global preferences.

For TSV imports, use one abbreviation and expansion per line, separated by a tab. An optional first row may be `abbreviation<TAB>expansion`. Use literal `\n` and `\t` inside an expansion for line breaks and tabs.

If the saved library cannot be decoded, the original file is preserved and automatic saving is disabled for that session. The error includes its path. Restore a valid backup there and relaunch; you can export any temporary work before doing so.

## Behavior and current limits

dText implements the core Typinator-style text expansion workflow with its own interface and file format. It is **not full Typinator feature or file-format compatibility**.

- Typinator `.tyset` imports, its macro language, packaged autocorrection dictionaries, arbitrary script execution, formulas, cloud/team sync, and iOS are not implemented.
- Rich text and images are stored as static attachments; template variables are for text and HTML.
- Cursor placement is for plain text. Tab/newline tokens insert characters rather than navigating or submitting forms.
- The service avoids its own editor and macOS Secure Input. Global operation depends on Accessibility approval and on the destination accepting ordinary delete/paste events.
- Some terminal applications, remote desktops, custom editors, and input methods may require compatibility work. Complex bidirectional text can affect cursor movement.
- The bounded in-memory typing buffer is cleared on application changes, mouse navigation, shortcuts, pause, and Secure Input. Keystrokes are not logged or sent over the network.
- Clipboard restoration checks the pasteboard change count, so a newer clipboard value is not overwritten. Destination applications that read the clipboard unusually late may need restoration disabled in Settings.
- Statistics measure expansion dispatches, not an accessibility-confirmed document diff; deleting a snippet also removes its usage totals.

## Verification

```sh
xcodebuild -project dText.xcodeproj -scheme dText \
  -destination 'platform=macOS' -derivedDataPath /tmp/dText-build test
```

Use the same signing team as normal Xcode runs. Unit tests cover matching, app scopes, separators, Unicode, regex time limits, dynamic fields, nesting, cursor offsets, import validation, persistence, corruption handling, and statistics. UI tests create/search a snippet, verify expansion with cursor placement in the playground, and check closing to the menu bar and reopening with the Dock icon. `--uitesting` uses an in-memory library and disables the global keyboard service, including when opening Settings.

Before distributing, test in TextEdit, Mail, a browser text area, and your preferred code editor with Accessibility granted. Verify immediate expansion, word separators, cancellation of input forms, clipboard restoration, rich text/image pasting, switching applications during an expansion, and Secure Input.

`scripts/generate-icon.swift` regenerates the original dText icon assets.
