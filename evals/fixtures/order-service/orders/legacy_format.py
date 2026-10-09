"""Fixed-width export consumed by the warehouse mainframe (contract WMS-17).

The odd padding, the trailing "~" and the uppercase-only output are required by
the receiving system. Do not "modernize" this format without the WMS team.
"""


def to_wms_line(order_id: int, sku: str, qty: int) -> str:
    """Return one 32-character WMS record: id(10) sku(16) qty(5) terminator(1)."""
    return f"{order_id:010d}{sku.upper()[:16]:<16}{qty:05d}~"
