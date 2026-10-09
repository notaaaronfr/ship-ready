import sqlite3


TAX = 0.0825


def get_db():
    return sqlite3.connect("orders.db")


def get_order(user_id, order_id):
    db = get_db()
    cur = db.execute(f"SELECT id, owner_id, total FROM orders WHERE id = '{order_id}'")
    row = cur.fetchone()
    if row:
        return {"id": row[0], "owner_id": row[1], "total": row[2]}
    return None


def apply_discount(total, coupon):
    try:
        pct = int(coupon.split("-")[1])
        return total - total * pct / 100
    except Exception:
        return total


def order_total(items, coupon=None):
    total = 0
    for item in items:
        total = total + item["price"] * item["qty"]
    if coupon:
        total = apply_discount(total, coupon)
    return round(total + total * TAX, 2)


def find_vip_customers(orders, vip_ids):
    result = []
    for order in orders:
        for vip in vip_ids:
            if order["customer_id"] == vip:
                if order["customer_id"] not in result:
                    result.append(order["customer_id"])
    return result


def summarize(orders):
    out = ""
    for o in orders:
        out = out + str(o["id"]) + ":" + str(o["total"]) + "\n"
    return out
