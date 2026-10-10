# Changelog

## [0.6.1](https://github.com/nimble-123/takt/compare/v0.6.0...v0.6.1) (2026-10-10)


### Fehlerbehebungen

* **cli:** take over all timesheet settings and reload them in the running app ([#208](https://github.com/nimble-123/takt/issues/208)) ([d421b53](https://github.com/nimble-123/takt/commit/d421b53054b1d0f84365af58d77ee94982ec39e3))

## [0.6.0](https://github.com/nimble-123/takt/compare/v0.5.1...v0.6.0) (2026-10-10)


### Neue Funktionen

* **analytics:** add project shares, top work items, insight and duration comparison ([#194](https://github.com/nimble-123/takt/issues/194)) ([0a45473](https://github.com/nimble-123/takt/commit/0a45473896e70dac48e63bb438d0cc54dd8ba994))
* **analytics:** add the flex account and absence days (AZ-05) ([#179](https://github.com/nimble-123/takt/issues/179)) ([d1081b2](https://github.com/nimble-123/takt/commit/d1081b2d1778b0eac1797985fa33072b0c55358e))
* **analytics:** add the vacation account (AZ-06) ([#181](https://github.com/nimble-123/takt/issues/181)) ([ce4862b](https://github.com/nimble-123/takt/commit/ce4862bf86f5bf97253f4b9b3f4dc765587de98f))
* **analytics:** archive the working time record at the month close (AZ-10) ([#187](https://github.com/nimble-123/takt/issues/187)) ([2f54b0d](https://github.com/nimble-123/takt/commit/2f54b0dd3cacc2e4c93a7135a553c1a06c830352))
* **analytics:** cap the flex account at the year change (AZ-08) ([#183](https://github.com/nimble-123/takt/issues/183)) ([8032a56](https://github.com/nimble-123/takt/commit/8032a56d67fbef9af49cbf4ea6e026d80344eb91))
* **analytics:** check working days against the ArbZG (AZ-02) ([#177](https://github.com/nimble-123/takt/issues/177)) ([3bb98ff](https://github.com/nimble-123/takt/commit/3bb98ffd88864253e47173e942259b064395daee))
* **analytics:** compute the working day with start, end, breaks and net time (AZ-01) ([#175](https://github.com/nimble-123/takt/issues/175)) ([e83d39d](https://github.com/nimble-123/takt/commit/e83d39ddedf24f28971cee35a562ec11c3dedafc))
* **analytics:** export the working time record as PDF and CSV (AZ-09) ([#180](https://github.com/nimble-123/takt/issues/180)) ([29db353](https://github.com/nimble-123/takt/commit/29db353dc007d1803536096546d2f8663095007c))
* **analytics:** pay out overtime from the flex account (AZ-07) ([#182](https://github.com/nimble-123/takt/issues/182)) ([40c1ebf](https://github.com/nimble-123/takt/commit/40c1ebf1c4cbca860287555236b095dc8f5e1435))
* **cli:** add the takt command line tool (CL-01–CL-06) ([#202](https://github.com/nimble-123/takt/issues/202)) ([d98eb37](https://github.com/nimble-123/takt/commit/d98eb37b87f00a0cf683c98bdee036d37fc63353))
* **cli:** import the Excel timesheet once (CL-07) ([#206](https://github.com/nimble-123/takt/issues/206)) ([7959d43](https://github.com/nimble-123/takt/commit/7959d43f0e95c1bbf2cd157aa3aa1a5f7bbce4c9))
* **cli:** ship takt in the app bundle and link it from the settings ([#204](https://github.com/nimble-123/takt/issues/204)) ([28e6a0e](https://github.com/nimble-123/takt/commit/28e6a0edc325507c6390e90ce8e9d8ec07ad8eb1))
* **core:** add statutory public holidays per federal state (AZ-03) ([#176](https://github.com/nimble-123/takt/issues/176)) ([9495e92](https://github.com/nimble-123/takt/commit/9495e92d8cb74aa0845c939e81419730eb086194))
* **store:** add the import segment source and an import store (AZ-04) ([#205](https://github.com/nimble-123/takt/issues/205)) ([171cb20](https://github.com/nimble-123/takt/commit/171cb205c0d8d27eb5a2529e2513166b78761d67))
* **store:** log corrections of times in the same transaction (AZ-04) ([#178](https://github.com/nimble-123/takt/issues/178)) ([f7c841f](https://github.com/nimble-123/takt/commit/f7c841ffa1cf5b86e81c559228e2c839da2d43bf))
* **system:** remind when no timer runs during working hours (TM-09) ([#173](https://github.com/nimble-123/takt/issues/173)) ([eb49f93](https://github.com/nimble-123/takt/commit/eb49f93b2c2d02c73ffa79a7d5a0d834276ac182))
* **ui:** add segments, parallel hint, idle pause origin and booking difference in the inspector (HW-02) ([#195](https://github.com/nimble-123/takt/issues/195)) ([a0c39f5](https://github.com/nimble-123/takt/commit/a0c39f5cdb800dd879f5e0eb60b1633d054e921c))
* **ui:** choose the start mode with cards in the onboarding ([#196](https://github.com/nimble-123/takt/issues/196)) ([0e69cc4](https://github.com/nimble-123/takt/commit/0e69cc48317f752857513682e873242659922610))
* **ui:** close the popover and search gaps to the design canvas ([#188](https://github.com/nimble-123/takt/issues/188)) ([a2b6141](https://github.com/nimble-123/takt/commit/a2b614117b5a5fe8fc19a6b9bf8f4f6e8725a187))
* **ui:** explain the inactivity options and add "Later" (TM-06) ([#191](https://github.com/nimble-123/takt/issues/191)) ([2ae70d8](https://github.com/nimble-123/takt/commit/2ae70d881a49b5b9f70b7e1951d64c3265be09ae))
* **ui:** open a stop panel for missing required fields and show the duration in the toast (TM-11) ([#197](https://github.com/nimble-123/takt/issues/197)) ([8901c39](https://github.com/nimble-123/takt/commit/8901c39cb3ce2c5eb1e0baeb74c9f5228dfe9441))
* **ui:** show parallel time and focus blocks today, uncheck bookings in the day close ([#192](https://github.com/nimble-123/takt/issues/192)) ([2d07e70](https://github.com/nimble-123/takt/commit/2d07e706e9f2dcdb80626c2c2b129b29ea19976f))


### Fehlerbehebungen

* **ui:** align stepper values and search work items from 3 characters ([#186](https://github.com/nimble-123/takt/issues/186)) ([612bf0c](https://github.com/nimble-123/takt/commit/612bf0c36f98e4b6057e6bee53b8c906c60e48fd))
* **ui:** align the analytics KPIs at the top ([#198](https://github.com/nimble-123/takt/issues/198)) ([f92599b](https://github.com/nimble-123/takt/commit/f92599b4f1d7e2e7517690bfb8de9fd0a9de1782))
* **ui:** scroll the day and week timeline to the current hour when the window opens ([#199](https://github.com/nimble-123/takt/issues/199)) ([855c15f](https://github.com/nimble-123/takt/commit/855c15f7a4653b9974936d1964aa06f78431c812))

## [0.5.1](https://github.com/nimble-123/takt/compare/v0.5.0...v0.5.1) (2026-10-09)


### Fehlerbehebungen

* **ado:** book differences in steps of 0.01 h (DO-20, DO-24) ([#157](https://github.com/nimble-123/takt/issues/157)) ([4a7ea10](https://github.com/nimble-123/takt/commit/4a7ea10b96c3ec2bde3d358b08a1271319b0045d))
* **ado:** give back only the Remaining Work a booking took (DO-22) ([#161](https://github.com/nimble-123/takt/issues/161)) ([7a14bee](https://github.com/nimble-123/takt/commit/7a14bee2740bae49aa0c1113763efb13e41d8842))
* **ado:** send only still pending records and skip backoff only when the network returns (DO-26) ([#152](https://github.com/nimble-123/takt/issues/152)) ([bd4aa30](https://github.com/nimble-123/takt/commit/bd4aa30d845c2ab03b3a978cce5623a7229ab977))
* **analytics:** compare with the previous calendar day, week or month (AN-01) ([#151](https://github.com/nimble-123/takt/issues/151)) ([24883c9](https://github.com/nimble-123/takt/commit/24883c9e5d89342d7070a653dfca740eeeb6a8d8))
* **app:** bring Takt to the front when opened from the menu bar menu ([#169](https://github.com/nimble-123/takt/issues/169)) ([0378b0a](https://github.com/nimble-123/takt/commit/0378b0a048227a202804d173ec87156a153abeb6))
* **app:** write the heartbeat apart from backup and network chores (TM-07) ([#167](https://github.com/nimble-123/takt/issues/167)) ([f7c14e2](https://github.com/nimble-123/takt/commit/f7c14e23205b161d62a118143581186a5f78e9a3))
* **core:** end the global pause once none of its entries is paused (TM-02) ([#154](https://github.com/nimble-123/takt/issues/154)) ([7474638](https://github.com/nimble-123/takt/commit/74746387087bf2af1de4ffc78ffd8937e5e3ec0d))
* **core:** fix launch recovery, split associations and NaN weights (TM-07) ([#163](https://github.com/nimble-123/takt/issues/163)) ([7335a91](https://github.com/nimble-123/takt/commit/7335a9185aed35f83b920b5a323f33d571a049a9))
* **core:** keep the segments of an entry from overlapping (HW-02) ([#159](https://github.com/nimble-123/takt/issues/159)) ([440e655](https://github.com/nimble-123/takt/commit/440e65552d9817518d862b960536067e8f317f06))
* keep full-text search after a rejected query, skip dates in branch names, log error details privately ([#168](https://github.com/nimble-123/takt/issues/168)) ([5f2b2f6](https://github.com/nimble-123/takt/commit/5f2b2f6b3a061f3312c9e4acef358e5af6f16efa))
* **store:** allow one open segment per entry and index segments by entry (TM-01) ([#166](https://github.com/nimble-123/takt/issues/166)) ([6135142](https://github.com/nimble-123/takt/commit/613514293ceb03e41e53bc28ab6ad2530ca702a9))
* **store:** keep the booking log when importing a backup (DO-24) ([#165](https://github.com/nimble-123/takt/issues/165)) ([f5c615c](https://github.com/nimble-123/takt/commit/f5c615c0a7e3a5c97c69e48208e41067ce6f7260))
* **ui:** book the day close with ⌘↩ and select rows with one click (DO-20) ([#160](https://github.com/nimble-123/takt/issues/160)) ([21a49b0](https://github.com/nimble-123/takt/commit/21a49b050c0d3314fbf7c31621ce6cecdc62b878))
* **ui:** context menu on pauses and readable badges in dark mode (HW-02) ([#164](https://github.com/nimble-123/takt/issues/164)) ([51abd4e](https://github.com/nimble-123/takt/commit/51abd4e22b046c6c8e98150780937e047fb34eec))
* **ui:** drop stale results of overlapping loads (HW-01, AN-06, ST-03) ([#162](https://github.com/nimble-123/takt/issues/162)) ([c1f27d9](https://github.com/nimble-123/takt/commit/c1f27d958bb42f80d7dc3ccd4aa260c981b32276))
* **ui:** keep popover undo and selection on what they refer to (TM-11, MB-05) ([#156](https://github.com/nimble-123/takt/issues/156)) ([37ae847](https://github.com/nimble-123/takt/commit/37ae84798295c945a5324a403d3007a9672eb949))
* **ui:** keep typed inspector text when another field saves (HW-02) ([#153](https://github.com/nimble-123/takt/issues/153)) ([ec3c73e](https://github.com/nimble-123/takt/commit/ec3c73e21ed70042250064fa642fafd496af8d27))
* **ui:** keep values set by a configuration profile in the session ([#155](https://github.com/nimble-123/takt/issues/155)) ([b39ed3b](https://github.com/nimble-123/takt/commit/b39ed3b668c18779b354cebc03f899873db30110))

## [0.5.0](https://github.com/nimble-123/takt/compare/v0.4.0...v0.5.0) (2026-10-09)


### Neue Funktionen

* **ui:** delete entries by right-click and move them across days in the week (HW-02, HW-03) ([#130](https://github.com/nimble-123/takt/issues/130)) ([b9ca66c](https://github.com/nimble-123/takt/commit/b9ca66ce6a260248f3c76573ca4a5a09a47d99b3))
* **ui:** show tooltips in the analysis (AN-03, AN-04) ([#131](https://github.com/nimble-123/takt/issues/131)) ([842937d](https://github.com/nimble-123/takt/commit/842937d3685af8c385de544b49fa535469bf5c0b))


### Fehlerbehebungen

* **ado:** keep bookings with an unknown outcome pending (DO-24, DO-26) ([#141](https://github.com/nimble-123/takt/issues/141)) ([092f0b5](https://github.com/nimble-123/takt/commit/092f0b5d2959cd4d79de4d3e26f5b54ff0e6b178))
* **ado:** stop double bookings and endless pending records (DO-26) ([#111](https://github.com/nimble-123/takt/issues/111)) ([882ec14](https://github.com/nimble-123/takt/commit/882ec14282e61f7222082cc87aa9d90554ba50bb))
* **analytics:** harden duplicate IDs, idle detection, CSV export and store checks ([#117](https://github.com/nimble-123/takt/issues/117)) ([7356d03](https://github.com/nimble-123/takt/commit/7356d0338a4d0782de05cb5471772179c3ce5c32))
* **core:** deliver timer snapshots in commit order ([#112](https://github.com/nimble-123/takt/issues/112)) ([2b0a5ed](https://github.com/nimble-123/takt/commit/2b0a5ed6daa4d8fd026b22f33289682131afa278))
* **core:** leave entries paused again since an idle event alone (TM-06) ([#142](https://github.com/nimble-123/takt/issues/142)) ([6e44053](https://github.com/nimble-123/takt/commit/6e44053d8b7bebe83d9d46dfecdb2cf43ee99e5c))
* **ui:** accessibility and localization of the main window ([#121](https://github.com/nimble-123/takt/issues/121)) ([82e0a7c](https://github.com/nimble-123/takt/commit/82e0a7c5830e0a512e45abc665bbcd92f30cc1d9))
* **ui:** accessibility of the menu bar and command palette ([#120](https://github.com/nimble-123/takt/issues/120)) ([c9df824](https://github.com/nimble-123/takt/commit/c9df824df879491ca839c9a208d786c2bcc8b05a))
* **ui:** book after every stop and share timer actions (DO-21, DO-10) ([#114](https://github.com/nimble-123/takt/issues/114)) ([13df4e8](https://github.com/nimble-123/takt/commit/13df4e8e2516fc6925b9b6ebb13f706a3c897232))
* **ui:** book the current amounts in the day close (DO-20) ([#139](https://github.com/nimble-123/takt/issues/139)) ([ccd5823](https://github.com/nimble-123/takt/commit/ccd5823ab47d8bd2c22e6c88a75d2e61ce09bc62))
* **ui:** do not write back values a field loaded without being edited ([#140](https://github.com/nimble-123/takt/issues/140)) ([32daf8e](https://github.com/nimble-123/takt/commit/32daf8e00660a0849c2587f864df5b2c5e9db539))
* **ui:** drop reloads for a range that is no longer shown ([#115](https://github.com/nimble-123/takt/issues/115)) ([1119894](https://github.com/nimble-123/takt/commit/11198946d4ffcef238a301aab347e81bd3e6429d))
* **ui:** keep the inspector binding honest across screens ([#127](https://github.com/nimble-123/takt/issues/127)) ([752f434](https://github.com/nimble-123/takt/commit/752f434a8bb03d097d845bb69089ec0d8cd63b45))
* **ui:** keep typed edits, count live and save times once (HW-02) ([#116](https://github.com/nimble-123/takt/issues/116)) ([5999096](https://github.com/nimble-123/takt/commit/5999096b6e9639ecf080262c08270d8b25ef7d67))
* **ui:** only delete with ⌫ where the selected entries are visible ([#138](https://github.com/nimble-123/takt/issues/138)) ([c49d7d2](https://github.com/nimble-123/takt/commit/c49d7d2503b9a38641a8da45eb92f620bbee0a98))

## [0.4.0](https://github.com/nimble-123/takt/compare/v0.3.0...v0.4.0) (2026-10-08)


### Neue Funktionen

* **ui:** open the inspector by double-clicking an entry (HW-02) ([#84](https://github.com/nimble-123/takt/issues/84)) ([f88be6c](https://github.com/nimble-123/takt/commit/f88be6cdb0d727922c29fb9b60db1eb669af1fa7))


### Fehlerbehebungen

* **ado:** verify tokens with the preview version of connectionData (DO-01) ([#82](https://github.com/nimble-123/takt/issues/82)) ([de92a06](https://github.com/nimble-123/takt/commit/de92a06a14bdc66170a657655dd98354fcd7f7dc))
* **ui:** keep day close rows at full height (UC-07) ([#80](https://github.com/nimble-123/takt/issues/80)) ([d0cbbfe](https://github.com/nimble-123/takt/commit/d0cbbfeb7153e313df1caae8382b8aa15ec8ad58))

## [0.3.0](https://github.com/nimble-123/takt/compare/v0.2.0...v0.3.0) (2026-10-07)


### Neue Funktionen

* **ui:** open today and week timelines at the current hour ([#72](https://github.com/nimble-123/takt/issues/72)) ([39a6a2e](https://github.com/nimble-123/takt/commit/39a6a2e61997b5ed99fb3c4e11f232041ef8807e))
* **ui:** set daily goal and weekly hours in 0.1 h steps ([#75](https://github.com/nimble-123/takt/issues/75)) ([8ce17cb](https://github.com/nimble-123/takt/commit/8ce17cb780aaf99f18c240d8eb12429d081f882a))
* **ui:** start timers with [@category](https://github.com/category), /project and #tag tokens (MB-09) ([#73](https://github.com/nimble-123/takt/issues/73)) ([68744ea](https://github.com/nimble-123/takt/commit/68744eafcba139f619049e251293ddcc52463bef))

## [0.2.0](https://github.com/nimble-123/takt/compare/v0.1.0...v0.2.0) (2026-10-07)


### Neue Funktionen

* **app:** add app icon and logo ([#60](https://github.com/nimble-123/takt/issues/60)) ([e129cff](https://github.com/nimble-123/takt/commit/e129cff7056aaf1841ccb275bdddb48047937030))

## 0.1.0 (2026-10-07)


### Neue Funktionen

* **ado:** book time to Azure DevOps with day close and offline queue ([#36](https://github.com/nimble-123/takt/issues/36)) ([16bcdf6](https://github.com/nimble-123/takt/commit/16bcdf63a551886ec54d9dd02892100758e21ac5))
* **ado:** connect Azure DevOps with a personal access token ([#34](https://github.com/nimble-123/takt/issues/34)) ([2cf6842](https://github.com/nimble-123/takt/commit/2cf6842de2746e5af42b7aafc3a3411d5ef61c18))
* **ado:** search work items with compact preview and suggestions ([#35](https://github.com/nimble-123/takt/issues/35)) ([2a8268a](https://github.com/nimble-123/takt/commit/2a8268a5cc455c52d0311b5b2dd2f1ccab44edcf))
* **analytics:** add analyses with charts and CSV/JSON export ([#32](https://github.com/nimble-123/takt/issues/32)) ([74ce028](https://github.com/nimble-123/takt/commit/74ce028ab8248c4918885f1471c7634e19e39324))
* **analytics:** add PDF report and target against weekly hours ([#47](https://github.com/nimble-123/takt/issues/47)) ([03226f3](https://github.com/nimble-123/takt/commit/03226f34140f1e35d5bca52c8b35db9295c6b44f))
* **core:** add timer engine, allocation and rounding ([#23](https://github.com/nimble-123/takt/issues/23)) ([b210a19](https://github.com/nimble-123/takt/commit/b210a19244bd61031d41f2df1dc4ee89ada155d0))
* **core:** assign category, project and tags by rules ([#46](https://github.com/nimble-123/takt/issues/46)) ([e269c8a](https://github.com/nimble-123/takt/commit/e269c8adf8046024b082930ee74b18ed3daea3c9))
* **store:** add full-text search over entries, catalog and work items ([#44](https://github.com/nimble-123/takt/issues/44)) ([7f6bba3](https://github.com/nimble-123/takt/commit/7f6bba30860f4d9bd2c213be924194f609120c2e))
* **store:** add schema v1, GRDB timer store, backups and JSON archive ([#26](https://github.com/nimble-123/takt/issues/26)) ([10080b3](https://github.com/nimble-123/takt/commit/10080b3501cc3124faecc97f45da87f0bd253a5d))
* **system:** detect inactivity, sleep and screen lock ([#29](https://github.com/nimble-123/takt/issues/29)) ([d1b85d5](https://github.com/nimble-123/takt/commit/d1b85d5834343ec899601cd8713c5887cb28d409))
* **system:** suggest work items from the checked-out Git branch ([#48](https://github.com/nimble-123/takt/issues/48)) ([5fa0427](https://github.com/nimble-123/takt/commit/5fa04276fb6ae3eb79faaaa0144ab014590d8d2b))
* **ui:** add command palette ([#45](https://github.com/nimble-123/takt/issues/45)) ([98009d6](https://github.com/nimble-123/takt/commit/98009d645ae49a3b84a21e2408c530f74dd41371))
* **ui:** add main window with timeline, week, entry list and inspector ([#30](https://github.com/nimble-123/takt/issues/30)) ([ce7d10f](https://github.com/nimble-123/takt/commit/ce7d10fbc466a4de7303ef4d7bdfca71f70222ad))
* **ui:** add menu bar status item, popover and stop with undo ([#28](https://github.com/nimble-123/takt/issues/28)) ([21538a2](https://github.com/nimble-123/takt/commit/21538a298cf9a1f02e5ddfca50ba668a501edfe2))
* **ui:** add onboarding and settings ([#33](https://github.com/nimble-123/takt/issues/33)) ([d929e12](https://github.com/nimble-123/takt/commit/d929e12af05933c47853f5861479703496d7ce8e))
* **ui:** add projects, categories and tags ([#31](https://github.com/nimble-123/takt/issues/31)) ([9958cfc](https://github.com/nimble-123/takt/commit/9958cfc41dde1e72dccb496ab179afbff15d5bbd))


### Fehlerbehebungen

* **release:** mark shell scripts as executable ([#58](https://github.com/nimble-123/takt/issues/58)) ([0933c9e](https://github.com/nimble-123/takt/commit/0933c9ec4c9f931396f9b05d3b2d3b7a26f4df11))
