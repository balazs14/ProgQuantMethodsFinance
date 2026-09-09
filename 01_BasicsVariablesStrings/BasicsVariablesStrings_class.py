# 1. hét: Alapok, változók, karakterláncok
# A class.py a bemutatott kódot és mind a tíz forrásfeladat megoldását tartalmazza.

# ============================================================
# Környezetellenőrzés: terminálpéldák
# python3 --version
# python3 -m venv .venv
# source .venv/bin/activate

# ============================================================
# Hello World, megjegyzések, sortörés

print("Hello World!")

# Ez egy megjegyzés.
print("Hello World!")  # kimenet

print( \
      "Hello World!" \
     )

# ============================================================
# Program: bemenet, feldolgozás, kimenet

portfolio_name = "Danube Value Fund"
portfolio_status = "paper trading"
print(portfolio_name)
print(portfolio_status)

# ============================================================
# Változók és típusok

value = 1
print(type(value))
value = "bond"
print(type(value))

bond_name = "Danube Treasury 2031"
coupon_rate = 0.0453
print(f"{bond_name}: {coupon_rate * 100:.2f}%")

# ============================================================
# Változónevek és NameError-példa

portfolio_value = 100000
portfolio_currency = "HUF"
print(portfolio_value, portfolio_currency)

# A következő kód szándékosan hibás; javított alakja:
message = "Hello World!"
print(message)

# ============================================================
# Karakterlánc-literálok és indexelés

text = "Portfolio"
print(text[0])
print(type(text[0]))

report = "Q1 return: 4.5%"
print(report)
print('Q1 return: 4.5%')

# ============================================================
# Keresés és szeletelés

isin = "HU0000403706"
start = isin.find("HU")
print("HU" in isin)
print(start)
print(isin[start:start + 2])

identifier = "DANUBE VALUE"
print(identifier[:6])
print(identifier[::-1])

# ============================================================
# String-metódusok

name = "  danube VALUE fund  "
clean = name.strip()
print(clean.title())
print(len(clean))
print(clean.upper())
print(clean.lower())
print(clean.replace("VALUE", "INCOME"))

# ============================================================
# Formázás és escape karakterek

first, last = "Dávid", "Burka"
print(f"Oktató: {last} {first}")

print("Jelentés:\n\tQ1 return: 4.5%")
print(r"c:\data\prices.csv")

# ============================================================
# Forrásfeladat 1: két sor kiírása

two_lines = "A piac ma nyitva van.\nA portfólió kockázata ellenőrzendő."
print(two_lines)

# ============================================================
# Forrásfeladat 2: az r előtag jelentése

raw_path = r"c:\data\prices.csv"
print(raw_path)

# ============================================================
# Forrásfeladat 3: egy karakter típusa

single_character = "H"
print(type(single_character))

# ============================================================
# Forrásfeladat 4: teljes név egy print utasítással

last_name = "burka"
first_name = "dávid"
print(last_name.title(), first_name.title())

# ============================================================
# Forrásfeladat 5: két szó megcserélése -- első órai fókusz

identifier = "DANUBE VALUE"
parts = identifier.split(" ")
print(parts[1] + " " + parts[0])

# ============================================================
# Forrásfeladat 6: string megfordítása

short_code = "ABC"
print(short_code[::-1])

# ============================================================
# Forrásfeladat 7: első szó nagybetűsítése -- első órai fókusz

manager_name = "burka dávid"
parts = manager_name.split(" ")
print(parts[0].upper() + " " + parts[1])

# ============================================================
# Forrásfeladat 8: monogram készítése

analyst_name = "burka dávid"
parts = analyst_name.split(" ")
print(parts[0][0].upper() + parts[1][0].upper())

# ============================================================
# Forrásfeladat 9: kisbetűs név javítása -- első órai fókusz

analyst_name = "burka dávid"
print(analyst_name.title())

# ============================================================
# Forrásfeladat 10: szóközök és hossz

label = "   Danube Value Fund   "
clean_label = label.strip()
print(len(clean_label))

# ============================================================
# Alternatív megoldások a string-metódusok nélküli gyakorláshoz

raw_name = "burka dávid"
parts = raw_name.split(" ")
fixed_name = parts[0][0].upper() + parts[0][1:] + " " + parts[1][0].upper() + parts[1][1:]
print(fixed_name)

raw_label = "   Danube Value Fund   "
left = 0
right = len(raw_label)
while left < right and raw_label[left] == " ":
    left += 1
while right > left and raw_label[right - 1] == " ":
    right -= 1
print(right - left)
