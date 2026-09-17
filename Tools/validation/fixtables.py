import segno.consts as c, qrref
# my level order L,M,Q,H -> segno key (format bits)
SEG_KEY = {0:1, 1:0, 2:3, 3:2}
correct_ecc, correct_blocks = [], []
for lvl in range(4):
    row_e, row_b = [-1], [-1]
    for v in range(1, 41):
        groups = c.ECC[v][SEG_KEY[lvl]]
        blocks = sum(g.num_blocks for g in groups)
        eccs = {g.num_total - g.num_data for g in groups}
        assert len(eccs) == 1, (v, lvl, eccs)
        row_e.append(eccs.pop()); row_b.append(blocks)
    correct_ecc.append(row_e); correct_blocks.append(row_b)

names = "LMQH"
bad = 0
for lvl in range(4):
    for v in range(1, 41):
        if qrref.ECC_CW_PER_BLOCK[lvl][v] != correct_ecc[lvl][v]:
            print(f"ECC_CW[{names[lvl]}][v{v}] mine={qrref.ECC_CW_PER_BLOCK[lvl][v]} correct={correct_ecc[lvl][v]}"); bad += 1
        if qrref.ECC_BLOCKS[lvl][v] != correct_blocks[lvl][v]:
            print(f"BLOCKS[{names[lvl]}][v{v}] mine={qrref.ECC_BLOCKS[lvl][v]} correct={correct_blocks[lvl][v]}"); bad += 1
        # cross-check data capacity against segno's own group data
        groups = c.ECC[v][SEG_KEY[lvl]]
        seg_data = sum(g.num_blocks * g.num_data for g in groups)
        seg_total = sum(g.num_blocks * g.num_total for g in groups)
        if seg_total != qrref.raw_data_modules(v) // 8:
            print(f"RAWCW[v{v}] mine={qrref.raw_data_modules(v)//8} segno={seg_total}"); bad += 1
        mine_data = seg_total - correct_ecc[lvl][v] * correct_blocks[lvl][v]
        if mine_data != seg_data:
            print(f"DATACW[{names[lvl]}][v{v}] derived={mine_data} segno={seg_data}"); bad += 1
print(f"\n{bad} table discrepancies")

print("\n--- corrected tables ---")
for row in correct_ecc:
    print("        [" + ", ".join(f"{x:2d}" for x in row) + "],")
print()
for row in correct_blocks:
    print("        [" + ", ".join(f"{x:2d}" for x in row) + "],")
