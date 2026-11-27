# Wiffletree for iPhone: design

Static HTML mockups of the iPhone app, for approval before any UI is built. Open [mockups/index.html](mockups/index.html) in a browser, from `file://` or with `python3 -m http.server` in `design/mockups/`. There is no build step.

- `mockups/styles.css` holds the Tidal tokens, the iPhone frame and the shared iOS components.
- `mockups/mockup.js` adds the icon sprite, the phone's status bar and island, and the Light / Dark / Both switch, which every page has and which is remembered.
- Colours come only from the host repo's `design/themes/wiffletree-tidal.json`. Tints and iOS materials are `color-mix` blends of two tokens. Signal red appears only in the logo joint.
- Every text and background pair used was checked in both variants at 4.5:1 or better. That includes the tints, the filled badges and buttons, the lock-screen notification material and the camera mask. The closest pair is dark accent on its own tint, at 4.55:1. The tickets sheet's status words and blue PR links are 5.31:1 or better on both the sheet and its rows.

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
| 4 | [Project](mockups/project.html) | Conversation, dictating, tickets sheet at medium and at large | The coordinator chat with one pinned tickets line at the top, which opens the desktop's tickets panel as a sheet. It has Markdown messages, a folded agent-activity line, an "agents working" bar and a composer with dictation and send. |
| 5 | [Inbox](mockups/inbox.html) | Needs you, answering and dismissing, answered | Questions with the coordinator's choices as buttons, plus a free-text answer. Publish and merge approvals have Deny and Approve. Only questions swipe to Dismiss. Answered history is grouped by day. |
| 6 | [Ticket detail](mockups/ticket.html) | Ticket in review, ticket with a pull request inside the tickets sheet | Pushed inside the tickets sheet. Status in the desktop's words, branch, each review cycle's verdict per verifier and round, blocking findings with location and fix commit, and the pull request's number, state, checks and target. Agents are listed at the end. |
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
7. **Merging into a protected branch opens GitHub.** Only an unprotected merge, such as one into a feature branch, is approved in the Inbox, matching "only the human merges into a protected branch".
8. **An answer sends at once, with no Undo.** Answering wakes the asker immediately on the host, so the app does not pretend it can take an answer back. A short send delay, like Mail's Undo Send, would be possible but is not drawn. Only questions can be dismissed; the host has no Dismiss for approvals or permissions, which are approved or denied.
9. **The notification text names the project and the kind (question or approval), not the question itself.** Is the project name acceptable in an alert that passes through CloudKit, or should it be fully generic ("A coordinator needs you on Studio Mac")?
10. **Notifications are asked for on the Paired screen,** not at first launch.
11. **The demo marker is a teal outlined tag, not a banner on every screen.** The one-line strip on Home disappears after a Mac is paired. The demo host stays in Hosts unless hidden in Settings.
12. **Connection names:** "On Wi-Fi", "Via Tailscale" (or "Via VPN" when the address is not a Tailscale one) and "Unreachable · last seen …".
13. **Access level is shown, not chosen, on the phone.** The confirm screen says what the Mac granted, and changes happen on the Mac. This assumes the Mac picks Control or View only at pairing.

### Tickets and pull requests

From using the app: in the pinned ticket list it was hard to tell a ticket with a pull request from one without. A Tickets tab was drawn and turned down; these calls follow Michael's review.

14. **No Tickets tab.** The tab bar stays Projects, Inbox, Usage and Settings, and Usage keeps its tab. Tickets stay with their project, in its conversation, as on the desktop.
15. **The pinned card is one line:** "Tickets · 3 in progress, 4 done", in the desktop's summary words ("4 done" alone when nothing is in progress, "3 in progress" alone when nothing is done). When a ticket waits on you it adds "1 needs you" in yellow with a question glyph. The phase, the progress bar and the moving ticket's line are gone; the line saves the space they took.
16. **Tapping the line opens a sheet with medium and large detents,** mirroring the desktop's pinned panel. It opens at medium with the done tickets folded under "› 4 done"; dragging up to large shows more, and "4 done" unfolds when tapped. The header is "Tickets · 3 in progress, 4 done" with "Live from Wiffletree" on the right. A row's PR link opens GitHub; the rest of the row pushes Ticket detail inside the sheet, with Tickets to go back.
17. **The desktop's own words and colour roles,** from `ticket_table.rs` and `ticket_state_color` in `crates/workspace-desktop`:

    | Ticket state | Status word | Colour |
    | --- | --- | --- |
    | `planned` | Planned | subtle |
    | `assigned` | Assigned | focus |
    | `ready_for_testing` | Ready for testing | focus |
    | `verifying` | Verifying, or "Verifying · round N" while a cycle runs | subtle |
    | `passed` | Passed | green |
    | `failed` | Failed | red |
    | `blocked` | Blocked | red |
    | `completed` | Completed | focus |
    | `accepted` | Accepted | green |
    | `closed` | Closed | subtle |

    The pull request reads "#212 open", "#12 draft", "#207 merged" or "#203 closed", underlined in the link colour (Tidal blue, as the desktop sets `link` to blue) with "↗" after it; before there is one, "Not published" in subtle grey. The phone puts each row on two lines, the title and then the status word and PR link, because the desktop's three columns leave a phone about 20 characters of title. The arrow keeps the link's full colour, where the desktop dims it to 70%, so it passes contrast.
18. **Which tickets are listed, as on the desktop.** In progress: every open ticket (not accepted or closed) except a planned one with no open pull request, whose work has not started. Done: accepted and closed tickets, counted from the tickets the coordinator owns.
19. **A ticket in review with an open pull request shows its own state.** The status word is always the ticket's state and the PR link is its own column, so a ticket verifying after it was published reads "Verifying · round 1" beside "#215 open ↗". An accepted ticket whose pull request is still open sits under done with "#212 open ↗".
20. **"Needs you" is the phone's one addition to the panel.** A ticket needs you when its `publishing.waiting` (a publish) or `merging.stage.item` (a merge) names an open Inbox item; the host already links both. The phone's `Ticket` decodes `merging` but not yet `publishing`. The mark sits after the title, and on the folded "4 done" row when a done ticket needs you, so an accepted ticket waiting to merge is not hidden.
21. **Ticket detail uses the same words and colours.** Its status chip is grey for Verifying (it was yellow), and its pull request reads "#212 open". The app's `stateLabel` differs from the desktop in two tones, Verifying (yellow) and Completed (green); building this should follow the table above.

## Open questions

- **Live Activity updates without a server of ours.** ActivityKit updates a Live Activity remotely only through APNs push-to-update tokens, which need a sender holding our APNs key. CloudKit subscriptions cannot update a Live Activity. Without a sender, the activity can change only while the app runs or gets background time, so it can go stale. Options are to drop the Live Activity from v1, accept it updating only on alert taps and background refresh, or revisit the tiny stateless sender from the research brief.
- **The pairing key check.** The confirm sheet shows a short key id "to match the one under the QR code on your Mac". That needs the desktop's Connect a phone panel to show the same id. If the QR code is trusted as it stands, the row can go.
- **A device-name field.** The phone sends a normalised device name ("Michael's iPhone"). Should the user be able to edit it at pairing?
- **Pairing without a camera.** Some cases have no camera available, such as the Simulator or a denied permission. The `code` method is not planned for iPhone, so a denied camera leaves no way to pair. Should there be a paste-the-payload fallback, or does Settings › Camera suffice?
- **A sleeping Mac.** The Unreachable screen asks "Is the Mac awake?". Whether remote access keeps the Mac awake is still undecided on the host side.
- **iPad.** These are iPhone-only. An iPad layout would use a sidebar (hosts and projects) with the conversation in the detail pane.
- **Dimming behind the medium sheet.** Drawn dimmed, as a sheet usually is. Leaving the conversation undimmed at medium would let you keep reading while the tickets are open.
- **A cross-host or cross-project view of what waits on you.** Settled for now as no Tickets tab (call 14). The Inbox and the "needs you" marks cover approvals; a pull request into a protected branch, which only you merge on GitHub, has no Inbox item and so no mark.
