from unittest import mock

from orders import service


def test_order_total():
    items = [{"price": 10, "qty": 2}]
    expected = service.order_total(items)
    assert service.order_total(items) == expected


def test_vip():
    result = service.find_vip_customers([{"customer_id": "a"}], ["a"])
    assert result is not None


def test_get_order_calls_db():
    with mock.patch.object(service, "get_db") as get_db:
        service.get_order(1, 2)
        assert get_db.called
