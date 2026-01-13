# 计算 30 以内可以被 3 整除的整数
arrys=[i for i in range(20) if i%3==0]
print(arrys)

# 过滤掉长度小于或等于3的字符串列表，并将剩下的转换成大写字母
strs=["hello","hi","apple","dog","sun","yes"]
new_strs=[s.upper() for s in strs if len(s)>3]
print(new_strs)