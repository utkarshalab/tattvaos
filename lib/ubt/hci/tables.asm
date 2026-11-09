; =============================================================================
; Utkarsha OS — lib/ubt/hci/tables.asm — made by gen_tables.py from hci.def
; =============================================================================
; Do not edit: change hci.def and run gen_tables.py.
; Each entry: code (2), major, minor, then the offsets in ubt_hci_strings of
; the name, the parameters and the return parameters (4 each): 16 bytes.
; =============================================================================

%ifndef LIB_UBT_HCI_TABLES_ASM
%define LIB_UBT_HCI_TABLES_ASM

section .rodata
align 4
global ubt_hci_cmds
global ubt_hci_cmds_n
ubt_hci_cmds_n: dd 283
ubt_hci_cmds:
    dw 0x0401
    db 1, 0
    dd 0, 8, 35
    dw 0x0402
    db 1, 0
    dd 37, 35, 52
    dw 0x0403
    db 1, 0
    dd 61, 78, 52
    dw 0x0404
    db 1, 0
    dd 117, 35, 52
    dw 0x0405
    db 1, 0
    dd 139, 151, 35
    dw 0x0406
    db 1, 0
    dd 208, 219, 35
    dw 0x0408
    db 1, 1
    dd 237, 256, 263
    dw 0x0409
    db 1, 0
    dd 279, 291, 35
    dw 0x040A
    db 1, 0
    dd 305, 317, 35
    dw 0x040B
    db 1, 0
    dd 333, 348, 263
    dw 0x040C
    db 1, 0
    dd 362, 256, 263
    dw 0x040D
    db 1, 0
    dd 381, 391, 263
    dw 0x040E
    db 1, 0
    dd 414, 256, 263
    dw 0x040F
    db 1, 0
    dd 428, 452, 35
    dw 0x0411
    db 1, 0
    dd 471, 486, 35
    dw 0x0413
    db 1, 0
    dd 495, 512, 35
    dw 0x0415
    db 1, 0
    dd 526, 486, 35
    dw 0x0417
    db 1, 0
    dd 547, 566, 35
    dw 0x0419
    db 1, 0
    dd 573, 589, 35
    dw 0x041A
    db 1, 1
    dd 622, 256, 263
    dw 0x041B
    db 1, 0
    dd 645, 486, 35
    dw 0x041C
    db 1, 2
    dd 666, 691, 35
    dw 0x041D
    db 1, 0
    dd 707, 486, 35
    dw 0x041F
    db 1, 0
    dd 727, 486, 35
    dw 0x0420
    db 1, 2
    dd 745, 486, 761
    dw 0x0428
    db 1, 2
    dd 796, 812, 35
    dw 0x0429
    db 1, 2
    dd 875, 892, 35
    dw 0x042A
    db 1, 2
    dd 953, 317, 35
    dw 0x042B
    db 2, 1
    dd 970, 983, 263
    dw 0x042C
    db 2, 1
    dd 1008, 256, 263
    dw 0x042D
    db 2, 1
    dd 1027, 256, 263
    dw 0x042E
    db 2, 1
    dd 1044, 1063, 263
    dw 0x042F
    db 2, 1
    dd 1080, 256, 263
    dw 0x0430
    db 2, 1
    dd 1097, 1114, 263
    dw 0x0433
    db 2, 1
    dd 1131, 256, 263
    dw 0x0434
    db 2, 1
    dd 1146, 317, 263
    dw 0x0435
    db 3, 0
    dd 1163, 1184, 35
    dw 0x043D
    db 4, 1
    dd 1186, 1184, 35
    dw 0x043E
    db 4, 1
    dd 1206, 1184, 35
    dw 0x043F
    db 4, 1
    dd 1227, 1242, 35
    dw 0x0440
    db 4, 1
    dd 1264, 256, 263
    dw 0x0441
    db 4, 1
    dd 1286, 1184, 1184
    dw 0x0442
    db 4, 1
    dd 1294, 1184, 1184
    dw 0x0443
    db 4, 1
    dd 1310, 35, 35
    dw 0x0444
    db 4, 1
    dd 1327, 1346, 35
    dw 0x0445
    db 4, 1
    dd 1383, 1404, 263
    dw 0x0801
    db 1, 0
    dd 1443, 1453, 35
    dw 0x0803
    db 1, 0
    dd 1474, 1485, 35
    dw 0x0804
    db 1, 0
    dd 1526, 486, 35
    dw 0x0807
    db 1, 0
    dd 1542, 1552, 35
    dw 0x0809
    db 1, 0
    dd 1621, 486, 1636
    dw 0x080B
    db 1, 0
    dd 1661, 291, 35
    dw 0x080C
    db 1, 0
    dd 1673, 486, 1690
    dw 0x080D
    db 1, 0
    dd 1717, 1735, 1753
    dw 0x080E
    db 1, 2
    dd 1771, 35, 1796
    dw 0x080F
    db 1, 2
    dd 1814, 1840, 52
    dw 0x0810
    db 1, 2
    dd 1849, 1184, 35
    dw 0x0811
    db 2, 1
    dd 1859, 1875, 1753
    dw 0x0C01
    db 1, 0
    dd 1927, 1942, 52
    dw 0x0C03
    db 1, 0
    dd 1949, 35, 52
    dw 0x0C05
    db 1, 0
    dd 1955, 1184, 52
    dw 0x0C08
    db 1, 0
    dd 1972, 486, 1753
    dw 0x0C09
    db 1, 0
    dd 1978, 35, 1992
    dw 0x0C0A
    db 1, 0
    dd 2008, 2023, 52
    dw 0x0C0D
    db 1, 0
    dd 2030, 2051, 2064
    dw 0x0C11
    db 1, 0
    dd 2086, 1184, 2108
    dw 0x0C12
    db 1, 0
    dd 2127, 2051, 2150
    dw 0x0C13
    db 1, 0
    dd 2169, 2186, 52
    dw 0x0C14
    db 1, 0
    dd 2195, 35, 2211
    dw 0x0C15
    db 1, 0
    dd 2229, 35, 2254
    dw 0x0C16
    db 1, 0
    dd 2273, 2299, 52
    dw 0x0C17
    db 1, 0
    dd 2309, 35, 2254
    dw 0x0C18
    db 1, 0
    dd 2327, 2299, 52
    dw 0x0C19
    db 1, 0
    dd 2346, 35, 2363
    dw 0x0C1A
    db 1, 0
    dd 2379, 2397, 52
    dw 0x0C1B
    db 1, 0
    dd 2404, 35, 2428
    dw 0x0C1C
    db 1, 0
    dd 2457, 2482, 52
    dw 0x0C1D
    db 1, 0
    dd 2502, 35, 2428
    dw 0x0C1E
    db 1, 0
    dd 2529, 2482, 52
    dw 0x0C1F
    db 1, 0
    dd 2557, 35, 2574
    dw 0x0C20
    db 1, 0
    dd 2590, 2608, 52
    dw 0x0C23
    db 1, 0
    dd 2615, 35, 2626
    dw 0x0C24
    db 1, 0
    dd 2643, 2655, 52
    dw 0x0C25
    db 1, 0
    dd 2663, 35, 2682
    dw 0x0C26
    db 1, 0
    dd 2699, 2719, 52
    dw 0x0C27
    db 1, 0
    dd 2727, 486, 2751
    dw 0x0C28
    db 1, 0
    dd 2779, 2804, 1753
    dw 0x0C2D
    db 1, 0
    dd 2823, 2837, 2853
    dw 0x0C31
    db 1, 0
    dd 2879, 2896, 52
    dw 0x0C33
    db 1, 0
    dd 2905, 2922, 52
    dw 0x0C35
    db 1, 0
    dd 2966, 1184, 35
    dw 0x0C36
    db 1, 0
    dd 2985, 486, 2751
    dw 0x0C37
    db 1, 0
    dd 3015, 2804, 1753
    dw 0x0C38
    db 1, 0
    dd 3046, 35, 3059
    dw 0x0C39
    db 1, 0
    dd 3074, 35, 1184
    dw 0x0C3A
    db 1, 0
    dd 3095, 1184, 52
    dw 0x0C3F
    db 1, 2
    dd 3117, 3139, 52
    dw 0x0C42
    db 1, 2
    dd 3146, 35, 1992
    dw 0x0C43
    db 1, 2
    dd 3169, 2023, 52
    dw 0x0C44
    db 1, 2
    dd 3193, 35, 3211
    dw 0x0C45
    db 1, 2
    dd 3227, 3246, 52
    dw 0x0C46
    db 1, 2
    dd 3253, 35, 1992
    dw 0x0C47
    db 1, 2
    dd 3273, 2023, 52
    dw 0x0C48
    db 1, 2
    dd 3294, 35, 3211
    dw 0x0C49
    db 1, 2
    dd 3314, 3246, 52
    dw 0x0C51
    db 2, 1
    dd 3335, 35, 3344
    dw 0x0C52
    db 2, 1
    dd 3367, 3377, 52
    dw 0x0C53
    db 2, 1
    dd 3391, 486, 35
    dw 0x0C55
    db 2, 1
    dd 3414, 35, 3211
    dw 0x0C56
    db 2, 1
    dd 3428, 3246, 52
    dw 0x0C57
    db 2, 1
    dd 3443, 35, 3458
    dw 0x0C58
    db 2, 1
    dd 3477, 35, 3499
    dw 0x0C59
    db 2, 1
    dd 3516, 3539, 52
    dw 0x0C5A
    db 2, 1
    dd 3547, 35, 3570
    dw 0x0C5B
    db 2, 1
    dd 3591, 3615, 52
    dw 0x0C5F
    db 2, 1
    dd 3627, 2837, 35
    dw 0x0C60
    db 2, 1
    dd 3642, 3656, 263
    dw 0x0C63
    db 3, 0
    dd 3670, 1942, 52
    dw 0x0C66
    db 3, 0
    dd 3692, 35, 3211
    dw 0x0C67
    db 3, 0
    dd 3715, 3246, 52
    dw 0x0C68
    db 3, 0
    dd 3739, 2837, 3757
    dw 0x0C6C
    db 4, 0
    dd 3798, 35, 3819
    dw 0x0C6D
    db 4, 0
    dd 3848, 3870, 52
    dw 0x0C6E
    db 4, 0
    dd 3890, 1184, 52
    dw 0x0C6F
    db 4, 0
    dd 3913, 1184, 52
    dw 0x0C70
    db 4, 0
    dd 3939, 1184, 1184
    dw 0x0C71
    db 4, 0
    dd 3957, 1184, 52
    dw 0x0C72
    db 4, 0
    dd 3981, 1184, 52
    dw 0x0C73
    db 4, 0
    dd 4005, 1184, 52
    dw 0x0C74
    db 4, 1
    dd 4028, 4049, 4059
    dw 0x0C75
    db 4, 1
    dd 4078, 4049, 4059
    dw 0x0C76
    db 4, 1
    dd 4102, 1184, 4059
    dw 0x0C77
    db 4, 1
    dd 4115, 35, 4138
    dw 0x0C78
    db 4, 1
    dd 4178, 4202, 4234
    dw 0x0C79
    db 4, 1
    dd 4254, 35, 4270
    dw 0x0C7A
    db 4, 1
    dd 4289, 4306, 52
    dw 0x0C7B
    db 4, 1
    dd 4316, 486, 2751
    dw 0x0C7C
    db 4, 1
    dd 4342, 2804, 1753
    dw 0x0C7D
    db 4, 1
    dd 4369, 35, 4388
    dw 0x0C7E
    db 5, 1
    dd 4429, 35, 2254
    dw 0x0C7F
    db 5, 1
    dd 4451, 2299, 52
    dw 0x0C80
    db 5, 1
    dd 4474, 35, 4498
    dw 0x0C81
    db 5, 1
    dd 4516, 4541, 52
    dw 0x0C82
    db 5, 3
    dd 4550, 4578, 52
    dw 0x0C83
    db 5, 2
    dd 4589, 1184, 52
    dw 0x0C84
    db 5, 3
    dd 4609, 4637, 52
    dw 0x1001
    db 1, 0
    dd 4644, 35, 4663
    dw 0x1002
    db 1, 2
    dd 4723, 35, 4743
    dw 0x1003
    db 1, 0
    dd 4764, 35, 4784
    dw 0x1004
    db 1, 2
    dd 4804, 4828, 4835
    dw 0x1005
    db 1, 0
    dd 4868, 35, 4885
    dw 0x1009
    db 1, 0
    dd 4938, 35, 263
    dw 0x100A
    db 3, 0
    dd 4951, 35, 4972
    dw 0x100B
    db 4, 0
    dd 5012, 35, 1184
    dw 0x100C
    db 5, 2
    dd 5030, 35, 5057
    dw 0x100D
    db 5, 2
    dd 5086, 35, 1184
    dw 0x100E
    db 5, 2
    dd 5107, 1184, 1184
    dw 0x100F
    db 5, 2
    dd 5129, 1184, 5157
    dw 0x1401
    db 1, 0
    dd 5178, 486, 5206
    dw 0x1402
    db 1, 0
    dd 5234, 486, 1753
    dw 0x1403
    db 1, 0
    dd 5263, 486, 5281
    dw 0x1405
    db 1, 0
    dd 5309, 486, 5319
    dw 0x1406
    db 1, 2
    dd 5344, 486, 5365
    dw 0x1407
    db 1, 2
    dd 5397, 5408, 5425
    dw 0x1408
    db 3, 0
    dd 5462, 486, 5487
    dw 0x140C
    db 4, 0
    dd 5512, 35, 1184
    dw 0x140D
    db 4, 1
    dd 5537, 5565, 52
    dw 0x1801
    db 1, 0
    dd 5604, 35, 3211
    dw 0x1802
    db 1, 0
    dd 5623, 3246, 52
    dw 0x1803
    db 1, 0
    dd 5643, 35, 52
    dw 0x1804
    db 2, 1
    dd 5659, 3246, 52
    dw 0x180A
    db 4, 1
    dd 5680, 5699, 1753
    dw 0x2001
    db 4, 0
    dd 5721, 1942, 52
    dw 0x2002
    db 4, 0
    dd 5739, 35, 5759
    dw 0x2003
    db 4, 0
    dd 5782, 35, 4784
    dw 0x2005
    db 4, 0
    dd 5805, 256, 52
    dw 0x2006
    db 4, 0
    dd 5824, 5842, 52
    dw 0x2007
    db 4, 0
    dd 5911, 35, 3499
    dw 0x2008
    db 4, 0
    dd 5932, 5948, 52
    dw 0x2009
    db 4, 0
    dd 5965, 5948, 52
    dw 0x200A
    db 4, 0
    dd 5981, 2896, 52
    dw 0x200B
    db 4, 0
    dd 5999, 6018, 52
    dw 0x200C
    db 4, 0
    dd 6065, 6084, 52
    dw 0x200D
    db 4, 0
    dd 6103, 6118, 35
    dw 0x200E
    db 4, 0
    dd 6227, 35, 52
    dw 0x200F
    db 4, 0
    dd 6249, 35, 6274
    dw 0x2010
    db 4, 0
    dd 6290, 35, 52
    dw 0x2011
    db 4, 0
    dd 6311, 6330, 52
    dw 0x2012
    db 4, 0
    dd 6344, 6330, 52
    dw 0x2013
    db 4, 0
    dd 6366, 6381, 35
    dw 0x2014
    db 4, 0
    dd 6440, 6466, 52
    dw 0x2015
    db 4, 0
    dd 6472, 486, 6492
    dw 0x2016
    db 4, 0
    dd 6516, 486, 35
    dw 0x2017
    db 4, 0
    dd 6540, 6551, 6566
    dw 0x2018
    db 4, 0
    dd 6583, 35, 6591
    dw 0x2019
    db 4, 0
    dd 6609, 6622, 35
    dw 0x201A
    db 4, 0
    dd 6652, 6665, 1753
    dw 0x201B
    db 4, 0
    dd 6681, 486, 1753
    dw 0x201C
    db 4, 0
    dd 6698, 35, 6723
    dw 0x201D
    db 4, 0
    dd 6741, 6758, 52
    dw 0x201E
    db 4, 0
    dd 6768, 6788, 52
    dw 0x201F
    db 4, 0
    dd 6817, 35, 6829
    dw 0x2020
    db 4, 1
    dd 6848, 6381, 1753
    dw 0x2021
    db 4, 1
    dd 6875, 219, 1753
    dw 0x2022
    db 4, 2
    dd 6900, 6919, 1753
    dw 0x2023
    db 4, 2
    dd 6944, 35, 6972
    dw 0x2024
    db 4, 2
    dd 6997, 7026, 52
    dw 0x2025
    db 4, 2
    dd 7042, 35, 35
    dw 0x2026
    db 4, 2
    dd 7061, 7079, 35
    dw 0x2027
    db 4, 2
    dd 7086, 7103, 52
    dw 0x2028
    db 4, 2
    dd 7147, 7167, 52
    dw 0x2029
    db 4, 2
    dd 7186, 35, 52
    dw 0x202A
    db 4, 2
    dd 7205, 35, 6274
    dw 0x202B
    db 4, 2
    dd 7228, 7167, 7245
    dw 0x202C
    db 4, 2
    dd 7260, 7167, 7245
    dw 0x202D
    db 4, 2
    dd 7278, 2896, 52
    dw 0x202E
    db 4, 2
    dd 7295, 2299, 52
    dw 0x202F
    db 4, 2
    dd 7314, 35, 7338
    dw 0x2030
    db 5, 0
    dd 7391, 486, 7403
    dw 0x2031
    db 5, 0
    dd 7431, 7450, 52
    dw 0x2032
    db 5, 0
    dd 7466, 7477, 35
    dw 0x2035
    db 5, 0
    dd 7512, 7539, 52
    dw 0x2036
    db 5, 0
    dd 7552, 1184, 7574
    dw 0x2037
    db 5, 0
    dd 7591, 7611, 52
    dw 0x2038
    db 5, 0
    dd 7656, 7611, 52
    dw 0x2039
    db 5, 0
    dd 7676, 1184, 52
    dw 0x203A
    db 5, 0
    dd 7698, 35, 4498
    dw 0x203B
    db 5, 0
    dd 7726, 35, 7747
    dw 0x203C
    db 5, 0
    dd 7763, 7781, 52
    dw 0x203D
    db 5, 0
    dd 7787, 35, 52
    dw 0x203E
    db 5, 0
    dd 7805, 7832, 52
    dw 0x203F
    db 5, 0
    dd 7858, 7883, 52
    dw 0x2040
    db 5, 0
    dd 7917, 7944, 52
    dw 0x2041
    db 5, 0
    dd 7959, 1184, 52
    dw 0x2042
    db 5, 0
    dd 7982, 8005, 52
    dw 0x2043
    db 5, 0
    dd 8041, 1184, 35
    dw 0x2044
    db 5, 0
    dd 8060, 8084, 35
    dw 0x2045
    db 5, 0
    dd 8137, 35, 52
    dw 0x2046
    db 5, 0
    dd 8168, 8195, 52
    dw 0x2047
    db 5, 0
    dd 8202, 8223, 52
    dw 0x2048
    db 5, 0
    dd 8243, 8223, 52
    dw 0x2049
    db 5, 0
    dd 8267, 35, 52
    dw 0x204A
    db 5, 0
    dd 8290, 35, 6274
    dw 0x204B
    db 5, 0
    dd 8317, 35, 8334
    dw 0x204C
    db 5, 0
    dd 8355, 35, 8384
    dw 0x204D
    db 5, 0
    dd 8403, 8433, 52
    dw 0x204E
    db 5, 0
    dd 8443, 8463, 52
    dw 0x2059
    db 5, 1
    dd 8484, 8511, 52
    dw 0x205A
    db 5, 1
    dd 8527, 8553, 1753
    dw 0x205B
    db 5, 1
    dd 8579, 8609, 1753
    dw 0x205C
    db 5, 1
    dd 8634, 8653, 1753
    dw 0x205D
    db 5, 1
    dd 8692, 8719, 52
    dw 0x205E
    db 5, 1
    dd 8749, 8770, 35
    dw 0x205F
    db 5, 1
    dd 8784, 8815, 52
    dw 0x2060
    db 5, 2
    dd 8824, 35, 8847
    dw 0x2061
    db 5, 2
    dd 8892, 486, 8912
    dw 0x2062
    db 5, 2
    dd 8952, 1184, 1184
    dw 0x2063
    db 5, 2
    dd 8970, 1184, 1184
    dw 0x2064
    db 5, 2
    dd 8993, 1184, 35
    dw 0x2065
    db 5, 2
    dd 9007, 9021, 9027
    dw 0x2066
    db 5, 2
    dd 9042, 486, 35
    dw 0x2067
    db 5, 2
    dd 9056, 219, 1753
    dw 0x2068
    db 5, 2
    dd 9070, 1184, 35
    dw 0x2069
    db 5, 2
    dd 9084, 1184, 35
    dw 0x206A
    db 5, 2
    dd 9103, 9120, 35
    dw 0x206B
    db 5, 2
    dd 9135, 1184, 35
    dw 0x206C
    db 5, 2
    dd 9154, 9176, 9182
    dw 0x206D
    db 5, 2
    dd 9197, 486, 35
    dw 0x206E
    db 5, 2
    dd 9217, 1184, 1753
    dw 0x206F
    db 5, 2
    dd 9240, 9264, 1753
    dw 0x2074
    db 5, 2
    dd 9285, 9305, 52
    dw 0x2075
    db 5, 2
    dd 9319, 486, 1184
    dw 0x2076
    db 5, 2
    dd 9344, 9365, 9380
    dw 0x2077
    db 5, 2
    dd 9420, 9365, 35
    dw 0x2078
    db 5, 2
    dd 9444, 9468, 1753
    dw 0x2079
    db 5, 2
    dd 9524, 9548, 1753
    dw 0x207A
    db 5, 2
    dd 9566, 9592, 1753
    dw 0x207B
    db 5, 2
    dd 9618, 1184, 52
    dw 0x207C
    db 5, 3
    dd 9641, 9674, 52
    dw 0x207D
    db 5, 3
    dd 9690, 9713, 52
    dw 0x207E
    db 5, 3
    dd 9752, 9771, 35
    dw 0x2089
    db 6, 0
    dd 9819, 35, 1184
    dw 0x208B
    db 6, 0
    dd 9841, 486, 35
global ubt_hci_events
global ubt_hci_events_n
ubt_hci_events_n: dd 65
ubt_hci_events:
    dw 0x0001
    db 1, 0
    dd 9863, 52, 9876
    dw 0x0002
    db 1, 0
    dd 9877, 9892, 9876
    dw 0x0003
    db 1, 0
    dd 9939, 9953, 9876
    dw 0x0004
    db 1, 0
    dd 9998, 10011, 9876
    dw 0x0005
    db 1, 0
    dd 208, 10033, 9876
    dw 0x0006
    db 1, 0
    dd 10060, 1753, 9876
    dw 0x0007
    db 1, 0
    dd 10074, 10086, 9876
    dw 0x0008
    db 1, 0
    dd 10111, 10126, 9876
    dw 0x0009
    db 1, 0
    dd 10149, 1753, 9876
    dw 0x000A
    db 1, 0
    dd 10174, 10196, 9876
    dw 0x000B
    db 1, 0
    dd 10221, 10237, 9876
    dw 0x000C
    db 1, 0
    dd 10266, 10281, 9876
    dw 0x000D
    db 1, 0
    dd 10337, 10356, 9876
    dw 0x000E
    db 1, 0
    dd 10429, 10442, 9876
    dw 0x000F
    db 1, 0
    dd 10467, 10478, 9876
    dw 0x0010
    db 1, 0
    dd 10506, 10515, 9876
    dw 0x0011
    db 1, 0
    dd 10522, 486, 9876
    dw 0x0012
    db 1, 0
    dd 10537, 10549, 9876
    dw 0x0013
    db 1, 0
    dd 10572, 10586, 9876
    dw 0x0014
    db 1, 0
    dd 10609, 10621, 9876
    dw 0x0015
    db 1, 0
    dd 10657, 10674, 9876
    dw 0x0016
    db 1, 0
    dd 10694, 256, 9876
    dw 0x0017
    db 1, 0
    dd 10706, 256, 9876
    dw 0x0018
    db 1, 1
    dd 10723, 10739, 9876
    dw 0x0019
    db 1, 0
    dd 10760, 10777, 9876
    dw 0x001A
    db 1, 0
    dd 10787, 10808, 9876
    dw 0x001B
    db 1, 0
    dd 10815, 10832, 9876
    dw 0x001C
    db 1, 0
    dd 10849, 10876, 9876
    dw 0x001D
    db 1, 0
    dd 10903, 10928, 9876
    dw 0x001E
    db 1, 0
    dd 10956, 486, 9876
    dw 0x0020
    db 1, 0
    dd 10970, 10996, 9876
    dw 0x0021
    db 1, 2
    dd 11010, 1184, 9876
    dw 0x0022
    db 1, 2
    dd 11029, 11042, 9876
    dw 0x0023
    db 1, 2
    dd 11096, 11116, 9876
    dw 0x002C
    db 1, 2
    dd 11158, 11177, 9876
    dw 0x002D
    db 1, 2
    dd 11253, 11271, 9876
    dw 0x002E
    db 2, 1
    dd 1859, 11327, 9876
    dw 0x002F
    db 2, 1
    dd 11404, 11416, 9876
    dw 0x0030
    db 2, 1
    dd 11478, 1753, 9876
    dw 0x0031
    db 2, 1
    dd 11490, 256, 9876
    dw 0x0032
    db 2, 1
    dd 11505, 983, 9876
    dw 0x0033
    db 2, 1
    dd 11521, 11534, 9876
    dw 0x0034
    db 2, 1
    dd 11549, 256, 9876
    dw 0x0035
    db 2, 1
    dd 11562, 256, 9876
    dw 0x0036
    db 2, 1
    dd 11573, 263, 9876
    dw 0x0038
    db 2, 1
    dd 11586, 2804, 9876
    dw 0x0039
    db 2, 1
    dd 11619, 486, 9876
    dw 0x003B
    db 2, 1
    dd 11643, 1063, 9876
    dw 0x003C
    db 2, 1
    dd 11658, 3656, 9876
    dw 0x003D
    db 2, 1
    dd 11674, 11695, 9876
    dw 0x003E
    db 4, 0
    dd 11713, 11721, 9876
    dw 0x0048
    db 3, 0
    dd 11745, 1184, 9876
    dw 0x0049
    db 4, 1
    dd 11766, 11790, 9876
    dw 0x004A
    db 4, 1
    dd 11824, 52, 9876
    dw 0x004B
    db 4, 1
    dd 11844, 1184, 9876
    dw 0x004C
    db 4, 1
    dd 11864, 1184, 9876
    dw 0x004D
    db 4, 1
    dd 11876, 11888, 9876
    dw 0x004E
    db 4, 1
    dd 11905, 263, 9876
    dw 0x004F
    db 4, 1
    dd 11929, 35, 9876
    dw 0x0050
    db 4, 1
    dd 11962, 3139, 9876
    dw 0x0051
    db 4, 1
    dd 11985, 12009, 9876
    dw 0x0052
    db 4, 1
    dd 12022, 486, 9876
    dw 0x0053
    db 5, 0
    dd 12051, 1184, 9876
    dw 0x0054
    db 5, 3
    dd 12069, 12087, 9876
    dw 0x00FF
    db 1, 0
    dd 12121, 12128, 9876
global ubt_hci_le_events
global ubt_hci_le_events_n
ubt_hci_le_events_n: dd 35
ubt_hci_le_events:
    dw 0x0001
    db 4, 0
    dd 9939, 12135, 9876
    dw 0x0002
    db 4, 0
    dd 12221, 12232, 9876
    dw 0x0003
    db 4, 0
    dd 12287, 12308, 9876
    dw 0x0004
    db 4, 0
    dd 10221, 10237, 9876
    dw 0x0005
    db 4, 0
    dd 12357, 12369, 9876
    dw 0x0006
    db 4, 1
    dd 12392, 12418, 9876
    dw 0x0007
    db 4, 2
    dd 12459, 12478, 9876
    dw 0x0008
    db 4, 2
    dd 12531, 12551, 9876
    dw 0x0009
    db 4, 2
    dd 12567, 12582, 9876
    dw 0x000A
    db 4, 2
    dd 12600, 12618, 9876
    dw 0x000B
    db 4, 2
    dd 12727, 12747, 9876
    dw 0x000C
    db 5, 0
    dd 12809, 7403, 9876
    dw 0x000D
    db 5, 0
    dd 12829, 12844, 9876
    dw 0x000E
    db 5, 0
    dd 12970, 12996, 9876
    dw 0x000F
    db 5, 0
    dd 13065, 13085, 9876
    dw 0x0010
    db 5, 0
    dd 13138, 8195, 9876
    dw 0x0011
    db 5, 0
    dd 13157, 35, 9876
    dw 0x0012
    db 5, 0
    dd 13170, 13189, 9876
    dw 0x0013
    db 5, 0
    dd 13222, 13244, 9876
    dw 0x0014
    db 5, 0
    dd 13264, 13282, 9876
    dw 0x0015
    db 5, 1
    dd 13303, 1184, 9876
    dw 0x0016
    db 5, 1
    dd 13322, 1184, 9876
    dw 0x0017
    db 5, 1
    dd 13337, 1753, 9876
    dw 0x0018
    db 5, 1
    dd 13356, 1184, 9876
    dw 0x0019
    db 5, 2
    dd 13388, 1184, 9876
    dw 0x001A
    db 5, 2
    dd 13404, 13416, 9876
    dw 0x001B
    db 5, 2
    dd 13443, 1184, 9876
    dw 0x001C
    db 5, 2
    dd 13463, 9120, 9876
    dw 0x001D
    db 5, 2
    dd 13486, 1184, 9876
    dw 0x001E
    db 5, 2
    dd 13507, 9120, 9876
    dw 0x001F
    db 5, 2
    dd 13521, 13547, 9876
    dw 0x0020
    db 5, 2
    dd 13571, 13591, 9876
    dw 0x0021
    db 5, 2
    dd 13619, 13638, 9876
    dw 0x0022
    db 5, 2
    dd 13694, 1184, 9876
    dw 0x0023
    db 5, 3
    dd 13713, 13728, 9876
global ubt_hci_strings
ubt_hci_strings:
    db "INQUIRY", 0
    db "lap:3,length:1,responses:1", 0
    db "-", 0
    db "INQUIRY_CANCEL", 0
    db "status:1", 0
    db "PERIODIC_INQUIRY", 0
    db "max:2,min:2,lap:3,length:1,responses:1", 0
    db "EXIT_PERIODIC_INQUIRY", 0
    db "CREATE_CONN", 0
    db "addr:6,packets:2,psrm:1,reserved:1,clock:2,role_switch:1", 0
    db "DISCONNECT", 0
    db "handle:2,reason:1", 0
    db "CREATE_CONN_CANCEL", 0
    db "addr:6", 0
    db "status:1,addr:6", 0
    db "ACCEPT_CONN", 0
    db "addr:6,role:1", 0
    db "REJECT_CONN", 0
    db "addr:6,reason:1", 0
    db "LINK_KEY_REPLY", 0
    db "addr:6,key:16", 0
    db "LINK_KEY_NEG_REPLY", 0
    db "PIN_REPLY", 0
    db "addr:6,length:1,pin:16", 0
    db "PIN_NEG_REPLY", 0
    db "CHANGE_CONN_PACKET_TYPE", 0
    db "handle:2,packets:2", 0
    db "AUTH_REQUESTED", 0
    db "handle:2", 0
    db "SET_CONN_ENCRYPT", 0
    db "handle:2,on:1", 0
    db "CHANGE_CONN_LINK_KEY", 0
    db "LINK_KEY_SELECTION", 0
    db "flag:1", 0
    db "REMOTE_NAME_REQ", 0
    db "addr:6,psrm:1,reserved:1,clock:2", 0
    db "REMOTE_NAME_REQ_CANCEL", 0
    db "READ_REMOTE_FEATURES", 0
    db "READ_REMOTE_EXT_FEATURES", 0
    db "handle:2,page:1", 0
    db "READ_REMOTE_VERSION", 0
    db "READ_CLOCK_OFFSET", 0
    db "READ_LMP_HANDLE", 0
    db "status:1,handle:2,lmp:1,reserved:4", 0
    db "SETUP_SYNC_CONN", 0
    db "handle:2,tx_bw:4,rx_bw:4,latency:2,voice:2,retrans:1,packets:2", 0
    db "ACCEPT_SYNC_CONN", 0
    db "addr:6,tx_bw:4,rx_bw:4,latency:2,voice:2,retrans:1,packets:2", 0
    db "REJECT_SYNC_CONN", 0
    db "IO_CAP_REPLY", 0
    db "addr:6,io:1,oob:1,auth:1", 0
    db "USER_CONFIRM_REPLY", 0
    db "USER_CONFIRM_NEG", 0
    db "USER_PASSKEY_REPLY", 0
    db "addr:6,passkey:4", 0
    db "USER_PASSKEY_NEG", 0
    db "REMOTE_OOB_REPLY", 0
    db "addr:6,c:16,r:16", 0
    db "REMOTE_OOB_NEG", 0
    db "IO_CAP_NEG_REPLY", 0
    db "CREATE_PHYSICAL_LINK", 0
    db "?", 0
    db "ENH_SETUP_SYNC_CONN", 0
    db "ENH_ACCEPT_SYNC_CONN", 0
    db "TRUNCATED_PAGE", 0
    db "addr:6,psrm:1,clock:2", 0
    db "TRUNCATED_PAGE_CANCEL", 0
    db "SET_CSB", 0
    db "SET_CSB_RECEIVE", 0
    db "START_SYNC_TRAIN", 0
    db "RECEIVE_SYNC_TRAIN", 0
    db "addr:6,timeout:2,window:2,interval:2", 0
    db "REMOTE_OOB_EXT_REPLY", 0
    db "addr:6,c192:16,r192:16,c256:16,r256:16", 0
    db "HOLD_MODE", 0
    db "handle:2,max:2,min:2", 0
    db "SNIFF_MODE", 0
    db "handle:2,max:2,min:2,attempt:2,timeout:2", 0
    db "EXIT_SNIFF_MODE", 0
    db "QOS_SETUP", 0
    db "handle:2,flags:1,service:1,token_rate:4,peak:4,latency:4,variation:4", 0
    db "ROLE_DISCOVERY", 0
    db "status:1,handle:2,role:1", 0
    db "SWITCH_ROLE", 0
    db "READ_LINK_POLICY", 0
    db "status:1,handle:2,policy:2", 0
    db "WRITE_LINK_POLICY", 0
    db "handle:2,policy:2", 0
    db "status:1,handle:2", 0
    db "READ_DEFAULT_LINK_POLICY", 0
    db "status:1,policy:2", 0
    db "WRITE_DEFAULT_LINK_POLICY", 0
    db "policy:2", 0
    db "FLOW_SPEC", 0
    db "SNIFF_SUBRATING", 0
    db "handle:2,latency:2,remote_timeout:2,local_timeout:2", 0
    db "SET_EVENT_MASK", 0
    db "mask:8", 0
    db "RESET", 0
    db "SET_EVENT_FILTER", 0
    db "FLUSH", 0
    db "READ_PIN_TYPE", 0
    db "status:1,type:1", 0
    db "WRITE_PIN_TYPE", 0
    db "type:1", 0
    db "READ_STORED_LINK_KEY", 0
    db "addr:6,all:1", 0
    db "status:1,max:2,read:2", 0
    db "WRITE_STORED_LINK_KEY", 0
    db "status:1,written:1", 0
    db "DELETE_STORED_LINK_KEY", 0
    db "status:1,deleted:2", 0
    db "WRITE_LOCAL_NAME", 0
    db "name:248", 0
    db "READ_LOCAL_NAME", 0
    db "status:1,name:248", 0
    db "READ_CONN_ACCEPT_TIMEOUT", 0
    db "status:1,timeout:2", 0
    db "WRITE_CONN_ACCEPT_TIMEOUT", 0
    db "timeout:2", 0
    db "READ_PAGE_TIMEOUT", 0
    db "WRITE_PAGE_TIMEOUT", 0
    db "READ_SCAN_ENABLE", 0
    db "status:1,scan:1", 0
    db "WRITE_SCAN_ENABLE", 0
    db "scan:1", 0
    db "READ_PAGE_SCAN_ACTIVITY", 0
    db "status:1,interval:2,window:2", 0
    db "WRITE_PAGE_SCAN_ACTIVITY", 0
    db "interval:2,window:2", 0
    db "READ_INQUIRY_SCAN_ACTIVITY", 0
    db "WRITE_INQUIRY_SCAN_ACTIVITY", 0
    db "READ_AUTH_ENABLE", 0
    db "status:1,auth:1", 0
    db "WRITE_AUTH_ENABLE", 0
    db "auth:1", 0
    db "READ_CLASS", 0
    db "status:1,class:3", 0
    db "WRITE_CLASS", 0
    db "class:3", 0
    db "READ_VOICE_SETTING", 0
    db "status:1,voice:2", 0
    db "WRITE_VOICE_SETTING", 0
    db "voice:2", 0
    db "READ_AUTO_FLUSH_TIMEOUT", 0
    db "status:1,handle:2,timeout:2", 0
    db "WRITE_AUTO_FLUSH_TIMEOUT", 0
    db "handle:2,timeout:2", 0
    db "READ_TX_POWER", 0
    db "handle:2,type:1", 0
    db "status:1,handle:2,level:1", 0
    db "SET_FLOW_CONTROL", 0
    db "enable:1", 0
    db "HOST_BUFFER_SIZE", 0
    db "acl_len:2,sco_len:1,acl_count:2,sco_count:2", 0
    db "HOST_NUM_COMPLETED", 0
    db "READ_LINK_SUPERVISION_TIMEOUT", 0
    db "WRITE_LINK_SUPERVISION_TIMEOUT", 0
    db "READ_NUM_IAC", 0
    db "status:1,num:1", 0
    db "READ_CURRENT_IAC_LAP", 0
    db "WRITE_CURRENT_IAC_LAP", 0
    db "SET_AFH_CHANNEL_CLASS", 0
    db "map:10", 0
    db "READ_INQUIRY_SCAN_TYPE", 0
    db "WRITE_INQUIRY_SCAN_TYPE", 0
    db "READ_INQUIRY_MODE", 0
    db "status:1,mode:1", 0
    db "WRITE_INQUIRY_MODE", 0
    db "mode:1", 0
    db "READ_PAGE_SCAN_TYPE", 0
    db "WRITE_PAGE_SCAN_TYPE", 0
    db "READ_AFH_ASSESSMENT", 0
    db "WRITE_AFH_ASSESSMENT", 0
    db "READ_EIR", 0
    db "status:1,fec:1,eir:240", 0
    db "WRITE_EIR", 0
    db "fec:1,eir:240", 0
    db "REFRESH_ENCRYPTION_KEY", 0
    db "READ_SSP_MODE", 0
    db "WRITE_SSP_MODE", 0
    db "READ_LOCAL_OOB", 0
    db "status:1,c:16,r:16", 0
    db "READ_INQUIRY_TX_POWER", 0
    db "status:1,level:1", 0
    db "WRITE_INQUIRY_TX_POWER", 0
    db "level:1", 0
    db "READ_DEFAULT_ERRONEOUS", 0
    db "status:1,reporting:1", 0
    db "WRITE_DEFAULT_ERRONEOUS", 0
    db "reporting:1", 0
    db "ENHANCED_FLUSH", 0
    db "SEND_KEYPRESS", 0
    db "addr:6,type:1", 0
    db "SET_EVENT_MASK_PAGE_2", 0
    db "READ_FLOW_CONTROL_MODE", 0
    db "WRITE_FLOW_CONTROL_MODE", 0
    db "READ_ENH_TX_POWER", 0
    db "status:1,handle:2,gfsk:1,dqpsk:1,dpsk8:1", 0
    db "READ_LE_HOST_SUPPORT", 0
    db "status:1,le:1,simultaneous:1", 0
    db "WRITE_LE_HOST_SUPPORT", 0
    db "le:1,simultaneous:1", 0
    db "SET_MWS_CHANNEL_PARAMS", 0
    db "SET_EXTERNAL_FRAME_CONFIG", 0
    db "SET_MWS_SIGNALING", 0
    db "SET_MWS_TRANSPORT_LAYER", 0
    db "SET_MWS_SCAN_FREQ_TABLE", 0
    db "SET_MWS_PATTERN_CONFIG", 0
    db "SET_RESERVED_LT_ADDR", 0
    db "lt_addr:1", 0
    db "status:1,lt_addr:1", 0
    db "DELETE_RESERVED_LT_ADDR", 0
    db "SET_CSB_DATA", 0
    db "READ_SYNC_TRAIN_PARAMS", 0
    db "status:1,interval:2,timeout:4,service:1", 0
    db "WRITE_SYNC_TRAIN_PARAMS", 0
    db "min:2,max:2,timeout:4,service:1", 0
    db "status:1,interval:2", 0
    db "READ_SC_SUPPORT", 0
    db "status:1,support:1", 0
    db "WRITE_SC_SUPPORT", 0
    db "support:1", 0
    db "READ_AUTH_PAYLOAD_TIMEOUT", 0
    db "WRITE_AUTH_PAYLOAD_TIMEOUT", 0
    db "READ_LOCAL_OOB_EXT", 0
    db "status:1,c192:16,r192:16,c256:16,r256:16", 0
    db "READ_EXT_PAGE_TIMEOUT", 0
    db "WRITE_EXT_PAGE_TIMEOUT", 0
    db "READ_EXT_INQUIRY_LENGTH", 0
    db "status:1,length:2", 0
    db "WRITE_EXT_INQUIRY_LENGTH", 0
    db "length:2", 0
    db "SET_ECOSYSTEM_BASE_INTERVAL", 0
    db "interval:2", 0
    db "CONFIGURE_DATA_PATH", 0
    db "SET_MIN_ENCRYPTION_KEY_SIZE", 0
    db "size:1", 0
    db "READ_LOCAL_VERSION", 0
    db "status:1,hci:1,revision:2,lmp:1,manufacturer:2,subversion:2", 0
    db "READ_LOCAL_COMMANDS", 0
    db "status:1,commands:64", 0
    db "READ_LOCAL_FEATURES", 0
    db "status:1,features:8", 0
    db "READ_LOCAL_EXT_FEATURES", 0
    db "page:1", 0
    db "status:1,page:1,max:1,features:8", 0
    db "READ_BUFFER_SIZE", 0
    db "status:1,acl_len:2,sco_len:1,acl_count:2,sco_count:2", 0
    db "READ_BD_ADDR", 0
    db "READ_DATA_BLOCK_SIZE", 0
    db "status:1,max_acl:2,block_len:2,blocks:2", 0
    db "READ_LOCAL_CODECS", 0
    db "READ_LOCAL_PAIRING_OPTIONS", 0
    db "status:1,options:1,max_key:1", 0
    db "READ_LOCAL_CODECS_V2", 0
    db "READ_LOCAL_CODEC_CAPS", 0
    db "READ_LOCAL_CONTROLLER_DELAY", 0
    db "status:1,min:3,max:3", 0
    db "READ_FAILED_CONTACT_COUNTER", 0
    db "status:1,handle:2,counter:2", 0
    db "RESET_FAILED_CONTACT_COUNTER", 0
    db "READ_LINK_QUALITY", 0
    db "status:1,handle:2,quality:1", 0
    db "READ_RSSI", 0
    db "status:1,handle:2,rssi:1", 0
    db "READ_AFH_CHANNEL_MAP", 0
    db "status:1,handle:2,mode:1,map:10", 0
    db "READ_CLOCK", 0
    db "handle:2,which:1", 0
    db "status:1,handle:2,clock:4,accuracy:2", 0
    db "READ_ENCRYPTION_KEY_SIZE", 0
    db "status:1,handle:2,size:1", 0
    db "GET_MWS_TRANSPORT_CONFIG", 0
    db "SET_TRIGGERED_CLOCK_CAPTURE", 0
    db "handle:2,enable:1,which:1,lpo:1,skip:1", 0
    db "READ_LOOPBACK_MODE", 0
    db "WRITE_LOOPBACK_MODE", 0
    db "ENABLE_DUT_MODE", 0
    db "WRITE_SSP_DEBUG_MODE", 0
    db "WRITE_SC_TEST_MODE", 0
    db "handle:2,dm1:1,esco:1", 0
    db "LE_SET_EVENT_MASK", 0
    db "LE_READ_BUFFER_SIZE", 0
    db "status:1,len:2,count:1", 0
    db "LE_READ_LOCAL_FEATURES", 0
    db "LE_SET_RANDOM_ADDR", 0
    db "LE_SET_ADV_PARAMS", 0
    db "min:2,max:2,type:1,own_type:1,peer_type:1,peer:6,channels:1,filter:1", 0
    db "LE_READ_ADV_TX_POWER", 0
    db "LE_SET_ADV_DATA", 0
    db "length:1,data:31", 0
    db "LE_SET_SCAN_RSP", 0
    db "LE_SET_ADV_ENABLE", 0
    db "LE_SET_SCAN_PARAMS", 0
    db "type:1,interval:2,window:2,own_type:1,filter:1", 0
    db "LE_SET_SCAN_ENABLE", 0
    db "enable:1,no_dups:1", 0
    db "LE_CREATE_CONN", 0
    db "interval:2,window:2,filter:1,peer_type:1,peer:6,own_type:1,min:2,max:2,latency:2,timeout:2,ce_min:2,ce_max:2", 0
    db "LE_CREATE_CONN_CANCEL", 0
    db "LE_READ_ACCEPT_LIST_SIZE", 0
    db "status:1,size:1", 0
    db "LE_CLEAR_ACCEPT_LIST", 0
    db "LE_ADD_ACCEPT_LIST", 0
    db "type:1,addr:6", 0
    db "LE_REMOVE_ACCEPT_LIST", 0
    db "LE_CONN_UPDATE", 0
    db "handle:2,min:2,max:2,latency:2,timeout:2,ce_min:2,ce_max:2", 0
    db "LE_SET_HOST_CHANNEL_CLASS", 0
    db "map:5", 0
    db "LE_READ_CHANNEL_MAP", 0
    db "status:1,handle:2,map:5", 0
    db "LE_READ_REMOTE_FEATURES", 0
    db "LE_ENCRYPT", 0
    db "key:16,data:16", 0
    db "status:1,data:16", 0
    db "LE_RAND", 0
    db "status:1,random:8", 0
    db "LE_START_ENC", 0
    db "handle:2,rand:8,ediv:2,ltk:16", 0
    db "LE_LTK_REPLY", 0
    db "handle:2,ltk:16", 0
    db "LE_LTK_NEG_REPLY", 0
    db "LE_READ_SUPPORTED_STATES", 0
    db "status:1,states:8", 0
    db "LE_RECEIVER_TEST", 0
    db "channel:1", 0
    db "LE_TRANSMITTER_TEST", 0
    db "channel:1,length:1,payload:1", 0
    db "LE_TEST_END", 0
    db "status:1,packets:2", 0
    db "LE_REMOTE_CONN_PARAM_REPLY", 0
    db "LE_REMOTE_CONN_PARAM_NEG", 0
    db "LE_SET_DATA_LENGTH", 0
    db "handle:2,octets:2,time:2", 0
    db "LE_READ_DEFAULT_DATA_LENGTH", 0
    db "status:1,octets:2,time:2", 0
    db "LE_WRITE_DEFAULT_DATA_LENGTH", 0
    db "octets:2,time:2", 0
    db "LE_READ_LOCAL_P256", 0
    db "LE_GENERATE_DHKEY", 0
    db "key:64", 0
    db "LE_ADD_RESOLVING", 0
    db "peer_type:1,peer:6,peer_irk:16,local_irk:16", 0
    db "LE_REMOVE_RESOLVING", 0
    db "peer_type:1,peer:6", 0
    db "LE_CLEAR_RESOLVING", 0
    db "LE_READ_RESOLVING_SIZE", 0
    db "LE_READ_PEER_RPA", 0
    db "status:1,rpa:6", 0
    db "LE_READ_LOCAL_RPA", 0
    db "LE_RESOLUTION_ON", 0
    db "LE_SET_RPA_TIMEOUT", 0
    db "LE_READ_MAX_DATA_LENGTH", 0
    db "status:1,tx_octets:2,tx_time:2,rx_octets:2,rx_time:2", 0
    db "LE_READ_PHY", 0
    db "status:1,handle:2,tx:1,rx:1", 0
    db "LE_SET_DEFAULT_PHY", 0
    db "all:1,tx:1,rx:1", 0
    db "LE_SET_PHY", 0
    db "handle:2,all:1,tx:1,rx:1,options:2", 0
    db "LE_SET_ADV_SET_RANDOM_ADDR", 0
    db "set:1,addr:6", 0
    db "LE_SET_EXT_ADV_PARAMS", 0
    db "status:1,power:1", 0
    db "LE_SET_EXT_ADV_DATA", 0
    db "set:1,operation:1,fragment:1,length:1,data:n", 0
    db "LE_SET_EXT_SCAN_RSP", 0
    db "LE_SET_EXT_ADV_ENABLE", 0
    db "LE_READ_MAX_ADV_DATA_LENGTH", 0
    db "LE_READ_NUM_ADV_SETS", 0
    db "status:1,sets:1", 0
    db "LE_REMOVE_ADV_SET", 0
    db "set:1", 0
    db "LE_CLEAR_ADV_SETS", 0
    db "LE_SET_PERIODIC_ADV_PARAMS", 0
    db "set:1,min:2,max:2,props:2", 0
    db "LE_SET_PERIODIC_ADV_DATA", 0
    db "set:1,operation:1,length:1,data:n", 0
    db "LE_SET_PERIODIC_ADV_ENABLE", 0
    db "enable:1,set:1", 0
    db "LE_SET_EXT_SCAN_PARAMS", 0
    db "LE_SET_EXT_SCAN_ENABLE", 0
    db "enable:1,dups:1,duration:2,period:2", 0
    db "LE_EXT_CREATE_CONN", 0
    db "LE_PERIODIC_CREATE_SYNC", 0
    db "options:1,sid:1,type:1,addr:6,skip:2,timeout:2,cte:1", 0
    db "LE_PERIODIC_CREATE_SYNC_CANCEL", 0
    db "LE_PERIODIC_TERMINATE_SYNC", 0
    db "sync:2", 0
    db "LE_ADD_PERIODIC_LIST", 0
    db "type:1,addr:6,sid:1", 0
    db "LE_REMOVE_PERIODIC_LIST", 0
    db "LE_CLEAR_PERIODIC_LIST", 0
    db "LE_READ_PERIODIC_LIST_SIZE", 0
    db "LE_READ_TX_POWER", 0
    db "status:1,min:1,max:1", 0
    db "LE_READ_RF_PATH_COMPENSATION", 0
    db "status:1,tx:2,rx:2", 0
    db "LE_WRITE_RF_PATH_COMPENSATION", 0
    db "tx:2,rx:2", 0
    db "LE_SET_PRIVACY_MODE", 0
    db "type:1,addr:6,mode:1", 0
    db "LE_PERIODIC_RECEIVE_ENABLE", 0
    db "sync:2,enable:1", 0
    db "LE_PERIODIC_SYNC_TRANSFER", 0
    db "handle:2,service:2,sync:2", 0
    db "LE_PERIODIC_SET_INFO_TRANSFER", 0
    db "handle:2,service:2,set:1", 0
    db "LE_SET_PAST_PARAMS", 0
    db "handle:2,mode:1,skip:2,timeout:2,cte:1", 0
    db "LE_SET_DEFAULT_PAST_PARAMS", 0
    db "mode:1,skip:2,timeout:2,cte:1", 0
    db "LE_GENERATE_DHKEY_V2", 0
    db "key:64,type:1", 0
    db "LE_MODIFY_SLEEP_CLOCK_ACCURACY", 0
    db "action:1", 0
    db "LE_READ_BUFFER_SIZE_V2", 0
    db "status:1,len:2,count:1,iso_len:2,iso_count:1", 0
    db "LE_READ_ISO_TX_SYNC", 0
    db "status:1,handle:2,seq:2,time:4,offset:3", 0
    db "LE_SET_CIG_PARAMS", 0
    db "LE_SET_CIG_PARAMS_TEST", 0
    db "LE_CREATE_CIS", 0
    db "LE_REMOVE_CIG", 0
    db "cig:1", 0
    db "status:1,cig:1", 0
    db "LE_ACCEPT_CIS", 0
    db "LE_REJECT_CIS", 0
    db "LE_CREATE_BIG", 0
    db "LE_CREATE_BIG_TEST", 0
    db "LE_TERMINATE_BIG", 0
    db "big:1,reason:1", 0
    db "LE_BIG_CREATE_SYNC", 0
    db "LE_BIG_TERMINATE_SYNC", 0
    db "big:1", 0
    db "status:1,big:1", 0
    db "LE_REQUEST_PEER_SCA", 0
    db "LE_SETUP_ISO_DATA_PATH", 0
    db "LE_REMOVE_ISO_DATA_PATH", 0
    db "handle:2,direction:1", 0
    db "LE_SET_HOST_FEATURE", 0
    db "bit:1,value:1", 0
    db "LE_READ_ISO_LINK_QUALITY", 0
    db "LE_ENH_READ_TX_POWER", 0
    db "handle:2,phy:1", 0
    db "status:1,handle:2,phy:1,current:1,max:1", 0
    db "LE_READ_REMOTE_TX_POWER", 0
    db "LE_SET_PATH_LOSS_PARAMS", 0
    db "handle:2,high:1,high_hyst:1,low:1,low_hyst:1,min_time:2", 0
    db "LE_SET_PATH_LOSS_ENABLE", 0
    db "handle:2,enable:1", 0
    db "LE_SET_TX_POWER_REPORTING", 0
    db "handle:2,local:1,remote:1", 0
    db "LE_TRANSMITTER_TEST_V4", 0
    db "LE_SET_DATA_RELATED_ADDR_CHANGES", 0
    db "set:1,reasons:1", 0
    db "LE_SET_DEFAULT_SUBRATE", 0
    db "min:2,max:2,latency:2,cont:2,timeout:2", 0
    db "LE_SUBRATE_REQUEST", 0
    db "handle:2,min:2,max:2,latency:2,cont:2,timeout:2", 0
    db "LE_CS_READ_LOCAL_CAPS", 0
    db "LE_CS_SECURITY_ENABLE", 0
    db "INQUIRY_DONE", 0
    db "", 0
    db "INQUIRY_RESULT", 0
    db "num:1,addr:6,psrm:1,reserved:2,class:3,clock:2", 0
    db "CONN_COMPLETE", 0
    db "status:1,handle:2,addr:6,link:1,encryption:1", 0
    db "CONN_REQUEST", 0
    db "addr:6,class:3,link:1", 0
    db "status:1,handle:2,reason:1", 0
    db "AUTH_COMPLETE", 0
    db "REMOTE_NAME", 0
    db "status:1,addr:6,name:248", 0
    db "ENCRYPT_CHANGE", 0
    db "status:1,handle:2,on:1", 0
    db "CHANGE_LINK_KEY_COMPLETE", 0
    db "LINK_KEY_TYPE_CHANGED", 0
    db "status:1,handle:2,flag:1", 0
    db "REMOTE_FEATURES", 0
    db "status:1,handle:2,features:8", 0
    db "REMOTE_VERSION", 0
    db "status:1,handle:2,version:1,manufacturer:2,subversion:2", 0
    db "QOS_SETUP_COMPLETE", 0
    db "status:1,handle:2,flags:1,service:1,token:4,peak:4,latency:4,variation:4", 0
    db "CMD_COMPLETE", 0
    db "credits:1,opcode:2,ret:n", 0
    db "CMD_STATUS", 0
    db "status:1,credits:1,opcode:2", 0
    db "HW_ERROR", 0
    db "code:1", 0
    db "FLUSH_OCCURRED", 0
    db "ROLE_CHANGE", 0
    db "status:1,addr:6,role:1", 0
    db "NUM_COMPLETED", 0
    db "num:1,handle:2,count:2", 0
    db "MODE_CHANGE", 0
    db "status:1,handle:2,mode:1,interval:2", 0
    db "RETURN_LINK_KEYS", 0
    db "num:1,addr:6,key:16", 0
    db "PIN_REQUEST", 0
    db "LINK_KEY_REQUEST", 0
    db "LINK_KEY_NOTIFY", 0
    db "addr:6,key:16,type:1", 0
    db "LOOPBACK_COMMAND", 0
    db "command:n", 0
    db "DATA_BUFFER_OVERFLOW", 0
    db "link:1", 0
    db "MAX_SLOTS_CHANGE", 0
    db "handle:2,slots:1", 0
    db "READ_CLOCK_OFFSET_COMPLETE", 0
    db "status:1,handle:2,offset:2", 0
    db "CONN_PACKET_TYPE_CHANGED", 0
    db "status:1,handle:2,packets:2", 0
    db "QOS_VIOLATION", 0
    db "PAGE_SCAN_REP_MODE_CHANGE", 0
    db "addr:6,psrm:1", 0
    db "FLOW_SPEC_COMPLETE", 0
    db "INQUIRY_RSSI", 0
    db "num:1,addr:6,psrm:1,reserved:1,class:3,clock:2,rssi:1", 0
    db "REMOTE_EXT_FEATURES", 0
    db "status:1,handle:2,page:1,max:1,features:8", 0
    db "SYNC_CONN_COMPLETE", 0
    db "status:1,handle:2,addr:6,link:1,interval:1,window:1,rx_len:2,tx_len:2,air:1", 0
    db "SYNC_CONN_CHANGED", 0
    db "status:1,handle:2,interval:1,window:1,rx_len:2,tx_len:2", 0
    db "status:1,handle:2,tx_latency:2,rx_latency:2,remote_timeout:2,local_timeout:2", 0
    db "INQUIRY_EXT", 0
    db "num:1,addr:6,psrm:1,reserved:1,class:3,clock:2,rssi:1,eir:240", 0
    db "KEY_REFRESH", 0
    db "IO_CAP_REQUEST", 0
    db "IO_CAP_RESPONSE", 0
    db "USER_CONFIRM", 0
    db "addr:6,value:4", 0
    db "USER_PASSKEY", 0
    db "REMOTE_OOB", 0
    db "SSP_COMPLETE", 0
    db "LINK_SUPERVISION_TIMEOUT_CHANGED", 0
    db "ENHANCED_FLUSH_COMPLETE", 0
    db "PASSKEY_NOTIFY", 0
    db "KEYPRESS_NOTIFY", 0
    db "REMOTE_HOST_FEATURES", 0
    db "addr:6,features:8", 0
    db "LE_META", 0
    db "subevent:1,parameters:n", 0
    db "NUM_COMPLETED_BLOCKS", 0
    db "TRIGGERED_CLOCK_CAPTURE", 0
    db "handle:2,which:1,clock:4,offset:2", 0
    db "SYNC_TRAIN_COMPLETE", 0
    db "SYNC_TRAIN_RECEIVED", 0
    db "CSB_RECEIVE", 0
    db "CSB_TIMEOUT", 0
    db "addr:6,lt_addr:1", 0
    db "TRUNCATED_PAGE_COMPLETE", 0
    db "PERIPHERAL_PAGE_RESPONSE_TIMEOUT", 0
    db "CSB_CHANNEL_MAP_CHANGE", 0
    db "INQUIRY_RESPONSE_NOTIFY", 0
    db "lap:3,rssi:1", 0
    db "AUTH_PAYLOAD_TIMEOUT_EXPIRED", 0
    db "SAM_STATUS_CHANGE", 0
    db "ENCRYPT_CHANGE_V2", 0
    db "status:1,handle:2,on:1,key_size:1", 0
    db "VENDOR", 0
    db "data:n", 0
    db "status:1,handle:2,role:1,peer_type:1,peer:6,interval:2,latency:2,timeout:2,accuracy:1", 0
    db "ADV_REPORT", 0
    db "num:1,type:1,addr_type:1,addr:6,length:1,data:n,rssi:1", 0
    db "CONN_UPDATE_COMPLETE", 0
    db "status:1,handle:2,interval:2,latency:2,timeout:2", 0
    db "LTK_REQUEST", 0
    db "handle:2,rand:8,ediv:2", 0
    db "REMOTE_CONN_PARAM_REQUEST", 0
    db "handle:2,min:2,max:2,latency:2,timeout:2", 0
    db "DATA_LENGTH_CHANGE", 0
    db "handle:2,tx_octets:2,tx_time:2,rx_octets:2,rx_time:2", 0
    db "LOCAL_P256_COMPLETE", 0
    db "status:1,key:64", 0
    db "DHKEY_COMPLETE", 0
    db "status:1,dhkey:32", 0
    db "ENH_CONN_COMPLETE", 0
    db "status:1,handle:2,role:1,peer_type:1,peer:6,local_rpa:6,peer_rpa:6,interval:2,latency:2,timeout:2,accuracy:1", 0
    db "DIRECTED_ADV_REPORT", 0
    db "num:1,type:1,addr_type:1,addr:6,direct_type:1,direct:6,rssi:1", 0
    db "PHY_UPDATE_COMPLETE", 0
    db "EXT_ADV_REPORT", 0
    db "num:1,props:2,addr_type:1,addr:6,primary:1,secondary:1,sid:1,power:1,rssi:1,interval:2,direct_type:1,direct:6,length:1,data:n", 0
    db "PERIODIC_SYNC_ESTABLISHED", 0
    db "status:1,sync:2,sid:1,addr_type:1,addr:6,phy:1,interval:2,accuracy:1", 0
    db "PERIODIC_ADV_REPORT", 0
    db "sync:2,power:1,rssi:1,cte:1,status:1,length:1,data:n", 0
    db "PERIODIC_SYNC_LOST", 0
    db "SCAN_TIMEOUT", 0
    db "ADV_SET_TERMINATED", 0
    db "status:1,set:1,handle:2,events:1", 0
    db "SCAN_REQUEST_RECEIVED", 0
    db "set:1,type:1,addr:6", 0
    db "CHANNEL_SELECTION", 0
    db "handle:2,algorithm:1", 0
    db "CONNLESS_IQ_REPORT", 0
    db "CONN_IQ_REPORT", 0
    db "CTE_REQUEST_FAILED", 0
    db "PERIODIC_SYNC_TRANSFER_RECEIVED", 0
    db "CIS_ESTABLISHED", 0
    db "CIS_REQUEST", 0
    db "acl:2,cis:2,cig:1,cis_id:1", 0
    db "CREATE_BIG_COMPLETE", 0
    db "TERMINATE_BIG_COMPLETE", 0
    db "BIG_SYNC_ESTABLISHED", 0
    db "BIG_SYNC_LOST", 0
    db "REQUEST_PEER_SCA_COMPLETE", 0
    db "status:1,handle:2,sca:1", 0
    db "PATH_LOSS_THRESHOLD", 0
    db "handle:2,path_loss:1,zone:1", 0
    db "TX_POWER_REPORTING", 0
    db "status:1,handle:2,reason:1,phy:1,level:1,flag:1,delta:1", 0
    db "BIGINFO_ADV_REPORT", 0
    db "SUBRATE_CHANGE", 0
    db "status:1,handle:2,factor:2,latency:2,cont:2,timeout:2", 0

%endif ; LIB_UBT_HCI_TABLES_ASM
