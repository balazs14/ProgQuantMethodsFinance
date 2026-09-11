# Solutions to the in-class exercises from BasicsVariablesStrings.tex.
# The examples use only syntax and string methods demonstrated in the class file.

# ============================================================
# Exercise 1: print a full name with one print call

last_name = "burka"
first_name = "david"
print(last_name.title(), first_name.title())

# ============================================================
# Exercise 2: change the type of one variable

value = 1
print(type(value))
value = "bond"
print(type(value))

# ============================================================
# Exercise 3: read a NameError

message = "Hello World!"
# print(mesage)  # Intentional error: the variable name is misspelled.
print(message)  # Corrected version.

# ============================================================
# Exercise 4: put two parts on separate lines

text = "The sun scorches the field Grasshoppers graze there"
text = text.replace("field Grasshoppers", "field\nGrasshoppers")
print(text)

# ============================================================
# Exercise 5: raw strings

raw_path = r"c:\data\prices.csv"
print(raw_path)

# ============================================================
# Exercise 6: the type of one character

single_character = "H"
print(type(single_character))

# ============================================================
# Exercise 7: swap two words

name = "Jane Doe"
parts = name.split(" ")
print(parts[1] + " " + parts[0])

# ============================================================
# Exercise 8: reverse a string

short_code = "ABC"
print(short_code[::-1])

# ============================================================
# Exercise 9: upper-case the first word

name = "Jane Doe"
parts = name.split(" ")
print(parts[0].upper() + " " + parts[1])

# ============================================================
# Exercise 10: initials

name = "Jane Doe"
parts = name.split(" ")
print(parts[0][0].upper() + parts[1][0].upper())

# ============================================================
# Exercise 11: fix capitalisation

# Capitalisation with the dedicated method
name = "jane doe"
print(name.title())

# Capitalisation without the dedicated method
name = "jane doe"
parts = name.split(" ")
fixed_name = parts[0][0].upper() + parts[0][1:] + " " + parts[1][0].upper() + parts[1][1:]
print(fixed_name)

# ============================================================
# Exercise 12: strip spaces and print the length

# Leading/trailing spaces with the dedicated method
label = "   Danube Value Fund   "
clean_label = label.strip()
print(len(clean_label))

# Leading/trailing spaces without the dedicated method
label = "   Danube Value Fund   "
left = 0
right = len(label)
while left < right and label[left] == " ":
    left += 1
while right > left and label[right - 1] == " ":
    right -= 1
print(right - left)
