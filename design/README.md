# Wiffletree for iPhone: design

Static HTML mockups of the iPhone app, for approval before any UI is built. Open [mockups/index.html](mockups/index.html) in a browser, from `file://` or with `python3 -m http.server` in `design/mockups/`. There is no build step.

- `mockups/styles.css` holds the Tidal tokens, the iPhone frame and the shared iOS components.
- `mockups/mockup.js` adds the icon sprite, the phone's status bar and island, and the Light / Dark / Both switch, which every page has and which is remembered.
- Colours come only from the host repo's `design/themes/wiffletree-tidal.json`. Tints and iOS materials are `color-mix` blends of two tokens. Signal red appears only in the logo joint.
- Every text and background pair used was checked in both variants at 4.5:1 or better. That includes the tints, the filled badges and buttons, the lock-screen notification material and the camera mask. The closest pair is dark accent on its own tint, at 4.55:1.

## The app's shape

- **No account, one or more paired Macs.** Each Mac is a *host*. With one host the app opens straight into it.
- **Per host, a tab bar:** Projects, Inbox, Usage and Settings. Each tab is a navigation stack. The host name at the top of Projects is a menu that switches hosts.
- **HIG idioms used:** large titles, inset grouped lists, sheets for pairing and adding a Mac, action sheets to confirm removal, swipe actions on rows, a segmented control in the Inbox and the system font throughout.
- **Status is never colour alone.** Every state has a glyph and words, such as On Wi-Fi, Via Tailscale, Verifying · round 2 or 12% left.

## Screens

| # | Page | Screens | What it is |
| --- | --- | --- | --- |
| 1 | [First run](mockups/first-run.html) | Welcome, local network explainer, system prompt, Scan QR code, confirm pairing, paired | Opening the app to a paired Mac. Welcome offers Scan QR code and Try a demo, with the note that away from home it works over Tailscale or any VPN. The explainer comes before the one-shot iOS prompt. The confirm sheet shows the host's name, the short key id and the addresses from the QR code. Paired names the access level and asks for notifications in context. |
| 2 | [Hosts](mockups/hosts.html) | Paired hosts, swipe to remove, unreachable host, add host | Each Mac with how it is reached now (On Wi-Fi, Via Tailscale, Unreachable · last seen), a needs-you badge and the demo host. An unreachable Mac lists the addresses tried and what to check. |
| 3 | [Home](mockups/home.html) | Projects, switch host, agents working | Projects grouped by Space, each with an attention badge, its state in words and the ticket progress bar. A "Need you" card leads to the Inbox, and a row shows the agents working. |
| 4 | [Project](mockups/project.html) | Conversation; tickets expanded while dictating | The coordinator chat with ticket status pinned at the top, as on the desktop. It has Markdown messages, a folded agent-activity line, an "agents working" bar and a composer with dictation and send. |
| 5 | [Inbox](mockups/inbox.html) | Needs you, answering and dismissing, answered | Questions with the coordinator's choices as buttons, plus a free-text answer. Publish and merge approvals have Deny and Approve. Answered history is grouped by day. |
| 6 | [Ticket detail](mockups/ticket.html) | Ticket in review, ticket with a pull request | Status, branch, each review cycle's verdict per verifier and round, blocking findings with location and fix commit, and the pull request's number, state, checks and target. Agents are listed at the end. |
| 7 | [Usage and Settings](mockups/usage-settings.html) | Usage, Settings, host settings and remove | Provider quota bars, showing what is left as the desktop does. App settings cover paired hosts with access level, notification kinds, appearance, the demo host and about. A host's page lets you remove it. |
| 8 | [Notifications](mockups/notifications.html) | Lock-screen notification, Live Activity, Dynamic Island compact and expanded | "Needs you" reaching a locked phone. The text is generic because it travels through CloudKit. |
| 9 | [Demo mode](mockups/demo.html) | Demo home, demo conversation, demo in Settings | The built-in demo host. Its marker is a small outlined DEMO tag in the focus teal, plus one line on Home that offers pairing. |

## Design calls made overnight, to confirm

These were decided so the mockups could be finished. Each one is easy to change.

1. **The tab bar has four tabs: Projects, Inbox, Usage and Settings.** Hosts is not a tab. It is reached from the host-name menu and from Settings, because most people have one Mac. Is that right, or should Hosts be the root when there are two or more?
2. **The Inbox spans all projects on the host.** It does not span all hosts. Other hosts' counts appear in the host menu and on the Hosts list. Should there be one Inbox across every paired Mac?
3. **Coordinator messages are full-width Markdown with a small avatar, like the desktop. Your messages are right-hand bubbles.** iMessage-style bubbles for both sides would read worse for long Markdown.
4. **Agent-to-agent traffic folds into one activity line per burst,** which expands to show the messages. This mirrors the desktop's "2 agent messages, 1 notice" line.
5. **Dictation is shown as our own mic button in the composer,** using on-device speech recognition with a live waveform. The alternative is the keyboard's own dictation key, which needs no microphone or speech permission. Our button is quicker to reach, but it adds two permission prompts.
6. **Agents are read-only on iPhone.** The phone can view who is working, but stopping, restarting and changing models stay on the Mac. Should Stop at least be available?
7. **Merging into a protected branch opens GitHub.** Only an unprotected merge is approved in the Inbox, matching "only the human merges into a protected branch".
8. **The notification text names the project and the kind (question or approval), not the question itself.** Is the project name acceptable in an alert that passes through CloudKit, or should it be fully generic ("A coordinator needs you on Studio Mac")?
9. **Notifications are asked for on the Paired screen,** not at first launch.
10. **The demo marker is a teal outlined tag, not a banner on every screen.** The one-line strip on Home disappears after a Mac is paired. The demo host stays in Hosts unless hidden in Settings.
11. **Connection names:** "On Wi-Fi", "Via Tailscale" (or "Via VPN" when the address is not a Tailscale one) and "Unreachable · last seen …".
12. **Access level is shown, not chosen, on the phone.** The confirm screen says what the Mac granted, and changes happen on the Mac. This assumes the Mac picks Control or View only at pairing.

## Open questions

- **Live Activity updates without a server of ours.** ActivityKit updates a Live Activity remotely only through APNs push-to-update tokens, which need a sender holding our APNs key. CloudKit subscriptions cannot update a Live Activity. Without a sender, the activity can change only while the app runs or gets background time, so it can go stale. Options are to drop the Live Activity from v1, accept it updating only on alert taps and background refresh, or revisit the tiny stateless sender from the research brief.
- **The pairing key check.** The confirm sheet shows a short key id "to match the one under the QR code on your Mac". That needs the desktop's Connect a phone panel to show the same id. If the QR code is trusted as it stands, the row can go.
- **A device-name field.** The phone sends a normalised device name ("Michael's iPhone"). Should the user be able to edit it at pairing?
- **Pairing without a camera.** Some cases have no camera available, such as the Simulator or a denied permission. The `code` method is not planned for iPhone, so a denied camera leaves no way to pair. Should there be a paste-the-payload fallback, or does Settings › Camera suffice?
- **A sleeping Mac.** The Unreachable screen asks "Is the Mac awake?". Whether remote access keeps the Mac awake is still undecided on the host side.
- **iPad.** These are iPhone-only. An iPad layout would use a sidebar (hosts and projects) with the conversation in the detail pane.
- **The Usage tab's weight.** Usage is a glance with two cards and a token total. It could become a section on Home instead of a tab, which would free the slot for Hosts or Tickets.
- **A cross-project Tickets list.** Tickets are reached only through their project. The desktop's Me lens, of pull requests waiting on you, may deserve its own place.
