# Lesson 1 class examples: Basics, Variables, and Strings.
# Follow-along code matching BasicsVariablesStrings.tex.

# ============================================================
# Getting started: Hello World

print("Hello World!")

# Comments and line continuation
# Hello World program
print("Hello World!")  # this line displays the text

print( \
      "Hello World!" \
     )

# ============================================================
# Variables

x = 1
x = "Corvinus"
print(x)

message = "Hello World!"
print(message)

# ============================================================
# Checking a variable's type

x = 1
print(type(x))   # <class 'int'>
print(x)         # 1

x = "Corvinus"
print(type(x))   # <class 'str'>
print(x)         # Corvinus

# ============================================================
# Strings: characters and indexing

x = "Hello :)"
y = x[0]
print(y)          # H
print(type(y))    # <class 'str'>

# ============================================================
# Strings: searching within a string

x = "Budapest Corvinus University"
print("Corvinus" in x)        # True
start = x.find("Corvinus")
print(start)                  # 9

# ============================================================
# Strings: slicing

x = "Budapest Corvinus University"
print(x[:])       # the whole string
print(x[:1])      # "B"
print(x[::2])     # every second character
start = x.find("Corvinus")
print(x[start:start + 8])   # "Corvinus"

# ============================================================
# Strings: string functions

x = " Budapest Corvinus University "
print(x.strip())     # remove leading/trailing spaces
print(x.upper())     # BUDAPEST CORVINUS UNIVERSITY
print(x.lower())     # budapest corvinus university
print("kis pista".title())     # Kis Pista
print(x.replace("Budapest", "Vienna"))
print("Budapest".upper())  # methods work on literals too

# ============================================================
# Strings: concatenation and str.format()

first_word, second_word, third_word = "Budapest", "Corvinus", "University"
print(first_word + " " + second_word + " " + third_word)

s = "My name is {}. {} {}."
print(s.format("Bond", "James", "Bond"))

s = "My name is {0}. {1} {0}."   # numbered placeholders
print(s.format("Bond", "James"))

# ============================================================
# Strings: f-strings and format parameters

first, last = "James", "Bond"
print(f"My name is {last}. {first} {last}.")

number = 5
print(f"Short decimal: {number:.2f}")   # Short decimal: 5.00
print(f"Long decimal: {number:.10f}")   # Long decimal: 5.0000000000

# ============================================================
# Strings: escape characters and raw strings

print("D\'Artagnan and the \"Three Musketeers\".")
print("c:\\temp\\file.txt")
print(r"c:\temp\file.txt")   # raw string: backslashes kept as-is
