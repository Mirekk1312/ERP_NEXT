"""Nastavenie firiem pre fakturáciu (idempotentné – dá sa spúšťať opakovane).

Spúšťa sa cez:  .\scripts\nas.ps1 py setup\firmy.py -Data data\firmy.json

- vlastné polia IČO / DIČ / Platca DPH na firme a zákazníkovi, Tax ID premenované na IČ DPH
- skupinová firma (data/firmy.json → "skupina") na súhrnné výkazy, firmy sa zaradia pod ňu
- firmy z data/firmy.json (existujúce sa aktualizujú, chýbajúce sa založia)
- adresy firiem (sídlo, kancelária)
- číslovanie faktúr a dobropisov: každá firma vlastný rad VF20260001 (ročne od 0001);
  interný názov dokladu ATAX-VF20260001, na faktúre pole Číslo faktúry + Variabilný symbol
- DPH 23 % pre platcov; staré šablóny VAT 20 % / 10 % z ERPNext sa vypnú
"""

import frappe
from frappe.custom.doctype.custom_field.custom_field import create_custom_fields
from frappe.custom.doctype.property_setter.property_setter import make_property_setter

DPH_SADZBA = 23
# Počítadlo frappe je podľa prefixu (ATAX-VF2026), teda zvlášť pre každú firmu a rok.
# Rok (.YYYY.) sa v ERPNext berie z dátumu vystavenia (posting_date).
FAKTURA_SERIE = ".ABBR.-VF.YYYY.####"

# Číslo faktúry = interný názov bez skratky firmy (ATAX-VF20260001 -> VF20260001),
# variabilný symbol = len číslice (20260001). Opravný doklad po zrušení: VF20260001-1.
CISLO_FAKTURY_SCRIPT = """
if doc.name and not doc.name.startswith("new-"):
    abbr = frappe.db.get_value("Company", doc.company, "abbr")
    cislo = doc.name[len(abbr) + 1:] if doc.name.startswith(abbr + "-") else doc.name
    if doc.cislo_faktury != cislo:
        doc.cislo_faktury = cislo
        doc.variabilny_symbol = "".join([c for c in cislo.split("-")[0] if c.isdigit()])
"""


def vlastne_polia():
    create_custom_fields(
        {
            "Company": [
                dict(fieldname="ico", label="IČO", fieldtype="Data", insert_after="tax_id"),
                dict(fieldname="dic", label="DIČ", fieldtype="Data", insert_after="ico"),
                dict(fieldname="platca_dph", label="Platca DPH", fieldtype="Check", insert_after="dic"),
            ],
            "Customer": [
                dict(fieldname="ico", label="IČO", fieldtype="Data", insert_after="tax_id", in_standard_filter=1),
                dict(fieldname="dic", label="DIČ", fieldtype="Data", insert_after="ico"),
            ],
            "Sales Invoice": [
                dict(fieldname="cislo_faktury", label="Číslo faktúry", fieldtype="Data", insert_after="naming_series",
                     read_only=1, no_copy=1, bold=1, in_list_view=1, in_standard_filter=1, search_index=1),
                dict(fieldname="variabilny_symbol", label="Variabilný symbol", fieldtype="Data",
                     insert_after="cislo_faktury", read_only=1, no_copy=1),
                dict(fieldname="customer_ico", label="IČO odberateľa", fieldtype="Data",
                     fetch_from="customer.ico", read_only=1, insert_after="tax_id"),
                dict(fieldname="customer_dic", label="DIČ odberateľa", fieldtype="Data",
                     fetch_from="customer.dic", read_only=1, insert_after="customer_ico"),
            ],
        },
        update=True,
    )
    for dt in ("Company", "Customer", "Sales Invoice"):
        make_property_setter(dt, "tax_id", "label", "IČ DPH", "Data", validate_fields_for_doctype=False)


def ciselne_rady():
    options = "\n".join([FAKTURA_SERIE, "ACC-SINV-.YYYY.-", "ACC-SINV-RET-.YYYY.-"])
    make_property_setter("Sales Invoice", "naming_series", "options", options, "Text", validate_fields_for_doctype=False)
    make_property_setter("Sales Invoice", "naming_series", "default", FAKTURA_SERIE, "Text", validate_fields_for_doctype=False)
    # Hľadanie a zobrazenie faktúr podľa čísla faktúry
    make_property_setter("Sales Invoice", None, "search_fields", "cislo_faktury,customer,customer_name",
                         "Data", for_doctype=True, validate_fields_for_doctype=False)

    if not frappe.conf.get("server_script_enabled"):
        frappe.throw("Serverové skripty nie sú zapnuté (server_script_enabled v common_site_config).")
    name = "Sales Invoice – číslo faktúry a VS"
    script = frappe.get_doc("Server Script", name) if frappe.db.exists("Server Script", name) else frappe.new_doc("Server Script")
    script.update(dict(__newname=name, name=name, script_type="DocType Event", reference_doctype="Sales Invoice",
                       doctype_event="Before Save", script=CISLO_FAKTURY_SCRIPT.strip(), disabled=0))
    script.save()


def nova_firma(name, abbr, is_group=0):
    return frappe.get_doc(
        dict(
            doctype="Company",
            company_name=name,
            abbr=abbr,
            is_group=is_group,
            country="Slovakia",
            default_currency="EUR",
            create_chart_of_accounts_based_on="Standard Template",
            chart_of_accounts="Standard with Numbers",
        )
    ).insert()


def skupina(s):
    """Skupinová firma na súhrnné vyhodnocovanie (konsolidované výkazy). Nefakturuje."""
    if not frappe.db.exists("Company", s["name"]):
        nova_firma(s["name"], s["abbr"], is_group=1)
        print(f"  založená skupina {s['name']}")
    dph(frappe.get_doc("Company", s["name"]))  # skupina nefakturuje – len vypne šablóny VAT z ERPNext
    return s["name"]


def firma(f, parent=None):
    if frappe.db.exists("Company", f["name"]):
        doc = frappe.get_doc("Company", f["name"])
        if doc.abbr != f["abbr"]:
            frappe.throw(f"Firma {f['name']} má skratku {doc.abbr}, v dátach je {f['abbr']}.")
    else:
        doc = nova_firma(f["name"], f["abbr"])
        print(f"  založená firma {doc.name}")
    doc.parent_company = parent
    doc.ico = f["ico"]
    doc.dic = f["dic"]
    doc.platca_dph = f["platca_dph"]
    doc.tax_id = f.get("ic_dph") or ""
    if f.get("website"):
        doc.website = f["website"]
    doc.save()
    return doc


def adresy(f):
    for a in f["adresy"]:
        title = f["name"]
        existing = frappe.db.get_value(
            "Address",
            {"address_title": title, "address_type": a["type"], "is_your_company_address": 1},
        )
        doc = frappe.get_doc("Address", existing) if existing else frappe.new_doc("Address")
        doc.update(
            dict(
                address_title=title,
                address_type=a["type"],
                address_line1=a["line1"],
                address_line2=a.get("line2") or "",
                city=a["city"],
                pincode=a["pincode"],
                country="Slovakia",
                is_your_company_address=1,
                is_primary_address=1 if a["type"] == "Billing" else 0,
            )
        )
        if not existing:
            doc.append("links", dict(link_doctype="Company", link_name=f["name"]))
        doc.save()


def dph(company):
    # Staré šablóny z ERPNext (VAT 20 % / 10 %) nie sú platné od 1. 1. 2025.
    for name in frappe.get_all("Sales Taxes and Charges Template", {"company": company.name}, pluck="name"):
        if not name.startswith("DPH "):
            frappe.db.set_value("Sales Taxes and Charges Template", name, {"disabled": 1, "is_default": 0})

    if not company.platca_dph:
        return

    account = f"DPH {DPH_SADZBA}% - {company.abbr}"
    if not frappe.db.exists("Account", account):
        parent = frappe.db.get_value(
            "Account", {"company": company.name, "is_group": 1, "account_name": "Duties and Taxes"}
        )
        frappe.get_doc(
            dict(
                doctype="Account",
                account_name=f"DPH {DPH_SADZBA}%",
                company=company.name,
                parent_account=parent,
                account_type="Tax",
                tax_rate=DPH_SADZBA,
            )
        ).insert()

    template = f"DPH {DPH_SADZBA}% - {company.abbr}"
    if not frappe.db.exists("Sales Taxes and Charges Template", template):
        frappe.get_doc(
            dict(
                doctype="Sales Taxes and Charges Template",
                title=f"DPH {DPH_SADZBA}%",
                company=company.name,
                is_default=1,
                taxes=[
                    dict(
                        charge_type="On Net Total",
                        account_head=account,
                        description=f"DPH {DPH_SADZBA}%",
                        rate=DPH_SADZBA,
                    )
                ],
            )
        ).insert()
    else:
        frappe.db.set_value("Sales Taxes and Charges Template", template, {"disabled": 0, "is_default": 1})


def run(data):
    vlastne_polia()
    ciselne_rady()
    parent = skupina(data["skupina"]) if data.get("skupina") else None
    for f in data["firmy"]:
        print(f"Firma {f['name']} ({f['abbr']})")
        company = firma(f, parent)
        adresy(f)
        dph(company)
    frappe.db.commit()

    for c in frappe.get_all(
        "Company", fields=["name", "abbr", "ico", "dic", "tax_id", "platca_dph", "parent_company"], order_by="lft"
    ):
        label = ("└ " if c.parent_company else "") + c.name
        templates = frappe.get_all(
            "Sales Taxes and Charges Template", {"company": c.name, "disabled": 0}, pluck="name"
        )
        print(f"  {c.abbr:6} {label:40} IČO {c.ico or '-':9} DIČ {c.dic or '-':11} "
              f"IČ DPH {c.tax_id or '-':13} DPH: {', '.join(templates) or '-'}")
