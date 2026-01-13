'''
字典推导式的语法格式如下：
{ key_expr: value_expr for value in collection }
或
{ key_expr: value_expr for value in collection if condition }
'''
names = ['Bob','Tom','alice','Jerry','Wendy','Smith']
# 将列表中各字符串值为键，各字符串的长度为值，组成键值对
name_dict={name:len(name) for name in names}
print(name_dict)

# 将上面脚本转换成传统语法
name_dict2={}
for name in names:
    name_dict2[name]=len(name)
print(name_dict2)

# 提供三个数字，以三个数字为键，三个数字的平方为值来创建字典
numbers=[1,2,3]
numbers_dict={n:n**2 for n in numbers}
print(numbers_dict) 

# 转化成传统语法
numbers2={1,2,3}
numbers_dict2={}
for n in numbers2:
    numbers_dict2[n]=n**2
print(numbers_dict2)