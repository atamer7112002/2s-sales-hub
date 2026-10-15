"""Verify a real disposable Odoo demo. Config stays outside the repository.

Temporarily edits/restores one phone; creates/confirms/cancels/deletes its own
quotation. Never prints credentials, PII, raw RPC faults or response bodies.
"""
import json
import socket
import sys
import xmlrpc.client

socket.setdefaulttimeout(30)


def verify(config_path):
    with open(config_path) as f:
        c = json.load(f)
    common = xmlrpc.client.ServerProxy(c['host'].rstrip('/') + '/xmlrpc/2/common')
    print('Version:', common.version()['server_version'], flush=True)
    uid = common.authenticate(c['database'], c['user'], c['password'], {})
    if not uid:
        raise RuntimeError('Valid authentication failed; check local configuration.')
    print('Valid authentication: PASS', flush=True)
    if common.authenticate(c['database'], c['user'], 'invalid-2s-test', {}):
        raise RuntimeError('Invalid credentials unexpectedly accepted.')
    print('Invalid authentication: PASS', flush=True)
    obj = xmlrpc.client.ServerProxy(c['host'].rstrip('/') + '/xmlrpc/2/object')

    def call(model, method, args, kwargs=None):
        return obj.execute_kw(c['database'], uid, c['password'], model, method,
                              args, kwargs or {})

    internal = call('res.users', 'has_group', ['base.group_user'])
    print('Internal group:', bool(internal), flush=True)
    customers = call('res.partner', 'search_read', [[['customer_rank', '>', 0]]],
                     {'fields': ['name', 'phone', 'city'], 'limit': 2})
    if not customers:
        raise RuntimeError('No eligible customers. Seed a synthetic customer/quotation first.')
    print('Customer search/read: PASS', flush=True)
    partner = customers[0]
    old_phone = partner['phone']
    try:
        if not call('res.partner', 'write', [[partner['id']], {'phone': '+20 100 000 0000'}]):
            raise RuntimeError('Phone write was not acknowledged.')
        saved = call('res.partner', 'read', [[partner['id']]], {'fields': ['phone']})
        if saved[0]['phone'] != '+20 100 000 0000':
            raise RuntimeError('Phone readback did not match.')
        print('Phone write/read: PASS', flush=True)
    finally:
        if not call('res.partner', 'write', [[partner['id']], {'phone': old_phone}]):
            raise RuntimeError('Phone restoration failed; review the disposable demo.')
        print('Original phone restored: PASS', flush=True)
    matches = call('res.partner', 'search_read', [[['customer_rank', '>', 0],
                   ['name', 'ilike', partner['name']]]], {'fields': ['id'], 'limit': 2})
    if not matches:
        raise RuntimeError('Customer name search failed.')
    print('Customer name search: PASS', flush=True)
    orders = call('sale.order', 'search_read', [[]],
                  {'fields': ['name', 'state', 'order_line'], 'limit': 5})
    print('Order list: PASS', flush=True)
    if not internal:
        raise RuntimeError('Use the internal Sales test account for the full flow.')
    # Own synthetic records exercise quantities, price, totals and confirmation.
    product_id = None
    order_id = None
    try:
        product_id = call('product.product', 'create',
                          [{'name': '2S API verification product', 'list_price': 100.0}])
        order_id = call('sale.order', 'create', [{'partner_id': partner['id'],
            'order_line': [[0, 0, {'product_id': product_id, 'product_uom_qty': 2,
                                   'price_unit': 100.0}]]}])
        details = call('sale.order', 'read', [[order_id]],
                       {'fields': ['partner_id', 'state', 'amount_total']})
        lines = call('sale.order.line', 'search_read', [[['order_id', '=', order_id]]],
                     {'fields': ['name', 'product_uom_qty', 'price_unit', 'price_subtotal']})
        if not lines or lines[0]['product_uom_qty'] != 2 or details[0]['amount_total'] < 200:
            raise RuntimeError('Order details/line verification failed.')
        print('Order details and lines: PASS', flush=True)
        call('sale.order', 'action_confirm', [[order_id]])
        result = call('sale.order', 'read', [[order_id]], {'fields': ['state']})
        if result[0]['state'] != 'sale':
            raise RuntimeError('Order did not reach confirmed state.')
        print('action_confirm and state readback: PASS', flush=True)
    finally:
        if order_id:
            call('sale.order', 'action_cancel', [[order_id]])
            call('sale.order', 'unlink', [[order_id]])
        if product_id:
            call('product.product', 'unlink', [[product_id]])
        print('Disposable record cleanup finished.', flush=True)
    print('LIVE CORE API VERIFICATION: PASS', flush=True)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('Usage: python3 tool/verify_odoo.py /path/to/private-config.json')
    try:
        verify(sys.argv[1])
    except xmlrpc.client.ProtocolError as e:
        sys.exit(f'LIVE VERIFICATION FAILED: HTTP {e.errcode}. Check API endpoint availability.')
    except xmlrpc.client.Fault:
        sys.exit('LIVE VERIFICATION FAILED: Odoo RPC fault. Check modules, permissions and demo data. No raw fault logged.')
    except (OSError, ValueError, KeyError):
        sys.exit('LIVE VERIFICATION FAILED: Check private configuration and server connectivity.')
    except RuntimeError as e:
        sys.exit('LIVE VERIFICATION FAILED: ' + str(e))
