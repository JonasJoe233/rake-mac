"""文案字典校验：en 和 zh-Hans key 一致、占位符一致、中文不含破折号。"""
import json, re, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
en, zh = d["en"], d["zh-Hans"]
bad = []
bad += ["只有 en：" + k for k in sorted(set(en) - set(zh))] + ["只有 zh-Hans：" + k for k in sorted(set(zh) - set(en))]
for k in set(en) & set(zh):
    if set(re.findall(r"\{\w+\}", en[k])) != set(re.findall(r"\{\w+\}", zh[k])):
        bad.append("占位符不一致：" + k)
    if "——" in zh[k]:
        bad.append("中文含破折号：" + k)
for b in bad: print("失败 " + b)
print("文案 %d 个 key，%s" % (len(en), "通过" if not bad else "失败"))
sys.exit(1 if bad else 0)
