# 计算数字 1,2,3 的平方数 (传统语法)
# numbers=[1,2,3]
# squares=[]
# for n in numbers:
#     squares.append(n**2)
# print(squares)
    
# # 计算数字 1,2,3 的平方数 (推导式)
# squares2={n**2 for n in (1,2,3)}
# print(squares2)  

# 判断不是 abc 的字母并输出 (传统语法)
letters='abracadabra'
for letter in letters:
    if letter not in 'abc': 
        print(letter,end=" ")
print()    
# 判断不是 abc 的字母并输出 (推导式)
new_letters=[letter for letter in letters if letter not in 'abc']
# 输出去掉 []
for l in new_letters:
    print(l,end=" ")
        