"""Služby a cenník (idempotentné – dá sa spúšťať opakovane).

Spúšťa sa cez:  .\\scripts\\nas.ps1 py setup\\cennik.py -Data data\\cennik_atax_2026.json

- merné jednotky (hod, ks, podanie, …) a skupina položiek
- služby (Item, neskladové) – spoločné pre všetky firmy
- predajný cenník (Price List) s cenami bez DPH; položka bez ceny (price: null) sa len založí,
  cena sa zadá na faktúre
"""

import frappe


def mj(name):
    if not frappe.db.exists("UOM", name):
        frappe.get_doc(dict(doctype="UOM", uom_name=name, must_be_whole_number=0 if name == "hod" else 1)).insert()


def skupina(name):
    if not frappe.db.exists("Item Group", name):
        frappe.get_doc(dict(doctype="Item Group", item_group_name=name, parent_item_group="All Item Groups")).insert()


def cennik(name):
    if not frappe.db.exists("Price List", name):
        frappe.get_doc(dict(doctype="Price List", price_list_name=name, currency="EUR", selling=1, enabled=1)).insert()


def polozka(p, group):
    values = dict(
        item_name=p["name"],
        item_group=group,
        stock_uom=p["uom"],
        description=p["name"] + (f"<br>{p['desc']}" if p.get("desc") else ""),
        is_stock_item=0,
        is_sales_item=1,
        is_purchase_item=0,
        include_item_in_manufacturing=0,
    )
    if frappe.db.exists("Item", p["code"]):
        doc = frappe.get_doc("Item", p["code"])
        doc.update(values)
        doc.save()
        return "upravená"
    frappe.get_doc(dict(doctype="Item", item_code=p["code"], **values)).insert()
    return "založená"


def cena(p, price_list, valid_from):
    if p.get("price") is None:
        return
    existing = frappe.db.get_value(
        "Item Price", {"item_code": p["code"], "price_list": price_list, "valid_from": valid_from}
    )
    doc = frappe.get_doc("Item Price", existing) if existing else frappe.new_doc("Item Price")
    doc.update(dict(item_code=p["code"], price_list=price_list, price_list_rate=p["price"],
                    uom=p["uom"], valid_from=valid_from, selling=1))
    doc.save()


def run(data):
    group = data["item_group"]
    skupina(group)
    cennik(data["price_list"])
    for uom in sorted({p["uom"] for p in data["polozky"]}):
        mj(uom)

    for p in data["polozky"]:
        stav = polozka(p, group)
        cena(p, data["price_list"], data["valid_from"])
        price = f"{p['price']:>6} €" if p.get("price") is not None else "  bez ceny"
        print(f"  {p['code']:5} {stav:9} {price}  {p['uom']:11} {p['name']}")
    frappe.db.commit()

    pocet = frappe.db.count("Item Price", {"price_list": data["price_list"]})
    print(f"Cenník {data['price_list']}: {pocet} cien, služieb v skupine {group}: "
          f"{frappe.db.count('Item', {'item_group': group})}")
