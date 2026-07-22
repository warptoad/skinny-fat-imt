# IMT gas comparison — bare / event / full vs vanilla lean-IMT

All numbers are on-chain `gasUsed` for one transaction, measured on matched scenarios (same tree sizes, same ops). Optimizer `runs: 2**32-1` on every package. The three **versions** differ only in how a tree's leaves are made available to off-chain clients:

-   **bare** — leaves stored **nowhere** (no events, no array). Just like in the original lean-imt.
-   **event** — leaves emitted as `NewLeaf` **logs** (the current production `SkinnyIMTPoseidon` / `FatIMTPoseidon`).
-   **full** — leaves persisted in a **storage array** _and_ emitted as logs (`…FullNode`), so clients can read them from state (`eth_getStorageAt` / `debug_storageRangeAt` / `getLeaves()`).

Every cell shows `gasUsed (Δ% vs lean, Δgas vs lean)`, compared against the single **vanilla lean-IMT / PoseidonT3** baseline (lean has no poseidon2Yul/sha256 build, so it anchors all three).

### vanilla lean-IMT baseline (PoseidonT3)

| insert · 128th leaf (deep) | insertMany · 18 into 126-tree | insertManyRepeated · 128 one call ‡ | update · leaf @ index 0 of 144-tree | updateMany · 8 in size-8 tree |
| -------------------------: | ----------------------------: | ----------------------------------: | ----------------------------------: | ----------------------------: |
|                    210,289 |                       986,165 |                           5,769,316 |                             390,278 |                     1,188,600 |

## skinny-IMT

### skinny — chance's poseidon (PoseidonT3)

| Scenario                            |             bare (floor) |             event (logs) |        full (storage+logs) |
| ----------------------------------- | -----------------------: | -----------------------: | -------------------------: |
| insert · 128th leaf (deep)          |   186,919 (-11.1%, −23k) |    191,168 (-9.1%, −19k) |       218,404 (+3.9%, +8k) |
| insertMany · 18 into 126-tree       |  552,865 (-43.9%, −433k) |  593,543 (-39.8%, −393k) |    1,003,444 (+1.8%, +17k) |
| insertManyRepeated · 128 one call ‡ | 403,741 (-93.0%, −5366k) | 408,261 (-92.9%, −5361k) | 3,566,494 (-38.2%, −2203k) |
| update · leaf @ index 0 of 144-tree |   349,677 (-10.4%, −41k) |    355,469 (-8.9%, −35k) |      362,686 (-7.1%, −28k) |
| updateMany · 8 in size-8 tree       |  334,709 (-71.8%, −854k) |  357,551 (-69.9%, −831k) |    402,314 (-66.2%, −786k) |

### skinny — zemse's poseidon2Yul

| Scenario                            |             bare (floor) |             event (logs) |        full (storage+logs) |
| ----------------------------------- | -----------------------: | -----------------------: | -------------------------: |
| insert · 128th leaf (deep)          |    191,054 (-9.1%, −19k) |    195,303 (-7.1%, −15k) |      222,539 (+5.8%, +12k) |
| insertMany · 18 into 126-tree       |  572,158 (-42.0%, −414k) |  612,836 (-37.9%, −373k) |    1,022,737 (+3.7%, +37k) |
| insertManyRepeated · 128 one call ‡ | 407,869 (-92.9%, −5361k) | 412,389 (-92.9%, −5357k) | 3,570,622 (-38.1%, −2199k) |
| update · leaf @ index 0 of 144-tree |    362,279 (-7.2%, −28k) |    368,071 (-5.7%, −22k) |      375,288 (-3.8%, −15k) |
| updateMany · 8 in size-8 tree       |  345,468 (-70.9%, −843k) |  368,310 (-69.0%, −820k) |    413,073 (-65.2%, −776k) |

### skinny — sha256

| Scenario                            |             bare (floor) |             event (logs) |        full (storage+logs) |
| ----------------------------------- | -----------------------: | -----------------------: | -------------------------: |
| insert · 128th leaf (deep)          |   59,213 (-71.8%, −151k) |   63,410 (-69.8%, −147k) |     90,646 (-56.9%, −120k) |
| insertMany · 18 into 126-tree       |  139,011 (-85.9%, −847k) |  178,861 (-81.9%, −807k) |    588,762 (-40.3%, −397k) |
| insertManyRepeated · 128 one call ‡ | 276,035 (-95.2%, −5493k) | 280,503 (-95.1%, −5489k) | 3,438,736 (-40.4%, −2331k) |
| update · leaf @ index 0 of 144-tree |   61,000 (-84.4%, −329k) |   65,530 (-83.2%, −325k) |     72,747 (-81.4%, −318k) |
| updateMany · 8 in size-8 tree       |  81,822 (-93.1%, −1107k) | 103,388 (-91.3%, −1085k) |   148,151 (-87.5%, −1040k) |

## fat-IMT

### fat — chance's poseidon (PoseidonT3)

| Scenario                            |              bare (floor) |              event (logs) |        full (storage+logs) |
| ----------------------------------- | ------------------------: | ------------------------: | -------------------------: |
| insert · 128th leaf (deep)          |    241,859 (+15.0%, +32k) |    246,086 (+17.0%, +36k) |     273,343 (+30.0%, +63k) |
| insertMany · 18 into 126-tree       | 1,408,403 (+42.8%, +422k) | 1,450,681 (+47.1%, +465k) |  1,860,549 (+88.7%, +874k) |
| insertManyRepeated · 128 one call ‡ |  6,034,572 (+4.6%, +265k) |  6,297,678 (+9.2%, +528k) | 9,190,353 (+59.3%, +3421k) |
| update · leaf @ index 0 of 144-tree |   248,546 (-36.3%, −142k) |   253,090 (-35.2%, −137k) |    260,253 (-33.3%, −130k) |
| updateMany · 8 in size-8 tree       |   261,658 (-78.0%, −927k) |   284,514 (-76.1%, −904k) |    329,237 (-72.3%, −859k) |

### fat — zemse's poseidon2Yul

| Scenario                            |              bare (floor) |              event (logs) |        full (storage+logs) |
| ----------------------------------- | ------------------------: | ------------------------: | -------------------------: |
| insert · 128th leaf (deep)          |    245,994 (+17.0%, +36k) |    250,277 (+19.0%, +40k) |     277,489 (+32.0%, +67k) |
| insertMany · 18 into 126-tree       | 1,427,696 (+44.8%, +442k) | 1,469,974 (+49.1%, +484k) |  1,879,842 (+90.6%, +894k) |
| insertManyRepeated · 128 one call ‡ |  6,038,700 (+4.7%, +269k) |  6,301,813 (+9.2%, +532k) | 9,194,488 (+59.4%, +3425k) |
| update · leaf @ index 0 of 144-tree |   253,629 (-35.0%, −137k) |   258,184 (-33.8%, −132k) |    265,392 (-32.0%, −125k) |
| updateMany · 8 in size-8 tree       |   265,792 (-77.6%, −923k) |   288,648 (-75.7%, −900k) |    333,371 (-72.0%, −855k) |

### fat — sha256

| Scenario                            |             bare (floor) |             event (logs) |        full (storage+logs) |
| ----------------------------------- | -----------------------: | -----------------------: | -------------------------: |
| insert · 128th leaf (deep)          |   114,153 (-45.7%, −96k) |   118,328 (-43.7%, −92k) |     145,585 (-30.8%, −65k) |
| insertMany · 18 into 126-tree       |     994,549 (+0.9%, +8k) |  1,034,187 (+4.9%, +48k) |  1,444,055 (+46.4%, +458k) |
| insertManyRepeated · 128 one call ‡ | 5,906,866 (+2.4%, +138k) | 6,169,920 (+6.9%, +401k) | 9,062,595 (+57.1%, +3293k) |
| update · leaf @ index 0 of 144-tree |  102,954 (-73.6%, −287k) |  107,446 (-72.5%, −283k) |    114,609 (-70.6%, −276k) |
| updateMany · 8 in size-8 tree       | 133,957 (-88.7%, −1055k) | 155,603 (-86.9%, −1033k) |    200,326 (-83.1%, −988k) |

† `insertManyRepeated` is apples-to-oranges: skinny/fat insert 128 **identical** leaves via their optimized repeated-insert path; lean forbids zero/duplicate leaves so its stand-in inserts 128 **distinct** leaves via `insertMany` (~128× the hashing). The row measures "lean has no repeated-insert primitive," not a like-for-like op.
