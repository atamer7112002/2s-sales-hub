#!/usr/bin/env python3
"""Read-only live check. Credentials are hidden terminal input, memory only."""
import datetime
import getpass
import json
from pathlib import Path
import socket
import sys
import urllib.request
import xmlrpc.client

URL = 'https://2s-sales-demo.odoo.com'
REPORT = Path(__file__).resolve().parents[1] / 'docs' / 'online_connectivity_result.json'
socket.setdefaulttimeout(25)


def main():
    report = {'server': URL, 'checked_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'authentication': 'not tested', 'customers': 'not tested',
              'subscription_access': 'undetermined'}
    stage = 'version'
    try:
        common = xmlrpc.client.ServerProxy(URL + '/xmlrpc/2/common')
        report['version'] = common.version()['server_version']
        print('XML-RPC POST version(): PASS — ' + report['version'], flush=True)
        stage = 'database discovery'
        req = urllib.request.Request(URL + '/web/database/list',
            data=json.dumps({'jsonrpc': '2.0', 'method': 'call', 'params': {}, 'id': 1}).encode(),
            headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=25) as response:
            databases = json.load(response).get('result')
        if not isinstance(databases, list) or not databases or not all(isinstance(v, str) for v in databases):
            raise RuntimeError('Database discovery unavailable; use the exact name from the Odoo database manager.')
        if len(databases) == 1:
            database = databases[0]
        else:
            print('Databases returned by server:', ', '.join(databases))
            database = input('Choose the exact database name: ').strip()
            if database not in databases:
                raise RuntimeError('Selected database was not returned by the server.')
        report['database'] = database
        report['database_source'] = 'POST /web/database/list response (not inferred from hostname)'
        print('Server-reported database: ' + database, flush=True)
        if '--probe' in sys.argv:
            return
        if not sys.stdin.isatty():
            raise RuntimeError('A local interactive terminal is required for secure input.')
        print('Enter the instance login and LOCAL Odoo password. Both inputs are hidden.')
        username = getpass.getpass('Odoo login (hidden): ').strip()
        password = getpass.getpass('Odoo password (hidden): ')
        if not username or not password:
            raise RuntimeError('Empty credentials; authentication not attempted.')
        stage = 'authentication'
        uid = common.authenticate(database, username, password, {})
        if not isinstance(uid, int) or isinstance(uid, bool) or uid <= 0:
            report['authentication'] = 'rejected'
            raise RuntimeError('Authentication rejected. Check the instance local password/login. Subscription status remains undetermined.')
        report['authentication'] = 'passed'
        print('Authentication: PASS (UID and login omitted)', flush=True)
        stage = 'customer read'
        obj = xmlrpc.client.ServerProxy(URL + '/xmlrpc/2/object')
        records = obj.execute_kw(database, uid, password, 'res.partner', 'search_read',
            [[['customer_rank', '>', 0]]], {'fields': ['id'], 'limit': 5, 'order': 'id'})
        if not isinstance(records, list):
            raise RuntimeError('Unexpected customer response type.')
        report['customers'] = 'passed'
        report['customer_sample_count'] = len(records)
        report['subscription_access'] = 'available for tested authentication and res.partner read'
        print('Customer domain read: PASS — sample count: ' + str(len(records)), flush=True)
        print('External API access: AVAILABLE for these tested operations.', flush=True)
        print('No customer values or credentials saved. No records were changed.')
    except xmlrpc.client.Fault as error:
        # Classify without logging the raw fault, which may contain PII or secrets.
        fault = error.faultString.lower()
        if any(term in fault for term in ('subscription', 'pricing plan', 'upgrade your plan', 'custom plan')):
            report['subscription_access'] = 'blocked: explicit plan/subscription fault'
            message = 'Odoo explicitly reported a subscription/plan restriction.'
        elif 'accessdenied' in fault or 'access denied' in fault:
            message = 'Access denied; credentials, local password or API rights need review. Plan restriction is not proven.'
        elif 'accesserror' in fault:
            message = 'Model access denied by Odoo permissions. Plan restriction is not proven.'
        elif 'customer_rank' in fault:
            message = 'Customer field unavailable; verify Sales is installed. Plan restriction is not proven.'
        else:
            message = 'Odoo RPC fault; raw details suppressed. Subscription status is undetermined.'
        report['failure'] = {'stage': stage, 'message': message}
        print(stage + ': FAILED — ' + message, flush=True)
    except xmlrpc.client.ProtocolError as error:
        report['failure'] = {'stage': stage, 'http_status': error.errcode}
        print(stage + ': HTTP ' + str(error.errcode) + '. Subscription status is undetermined.', flush=True)
    except RuntimeError as error:
        report['failure'] = {'stage': stage, 'message': str(error)}
        print(str(error), flush=True)
    except (OSError, ValueError, KeyError, TypeError):
        report['failure'] = {'stage': stage, 'message': 'Network or unexpected response failure; raw details suppressed.'}
        print('Connectivity/response failure. Subscription status is undetermined.', flush=True)
    finally:
        REPORT.write_text(json.dumps(report, indent=2) + '\n')
        print('Sanitized result saved to docs/online_connectivity_result.json', flush=True)


if __name__ == '__main__':
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print('\nLocal input cancelled. No credentials saved.')
