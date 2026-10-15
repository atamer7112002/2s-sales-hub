"""Create a least-privilege synthetic Odoo reviewer/demo; never logs credentials."""
import getpass,json,secrets,socket,xmlrpc.client
from pathlib import Path
from secure_keychain import get_password,set_password
socket.setdefaulttimeout(35)
URL='https://2s-sales-demo.odoo.com';DB='2s-sales-demo'
LOGIN='reviewer@2s-sales-demo.example';SERVICE='2S Sales Hub Odoo Reviewer'
root=Path(__file__).resolve().parents[1]
report={'server':URL,'database':DB,'reviewer_login':LOGIN,'status':'in_progress'}
secondary=None;stage='administrator authentication'
context={'no_reset_password':True,'mail_create_nosubscribe':True,'tracking_disable':True,'mail_notrack':True,'mail_create_nolog':True,'mail_notify_force_send':False,'send_email':False}
try:
 login=getpass.getpass('Administrator Odoo login (hidden): ');password=getpass.getpass('Administrator local password (hidden): ')
 common=xmlrpc.client.ServerProxy(URL+'/xmlrpc/2/common');uid=common.authenticate(DB,login,password,{})
 if not uid:raise RuntimeError('Administrator authentication rejected.')
 proxy=xmlrpc.client.ServerProxy(URL+'/xmlrpc/2/object')
 def call(model,method,args,kw=None):
  return proxy.execute_kw(DB,uid,password,model,method,args,dict(kw or {},context=context))
 def fields(model,names):return call(model,'fields_get',[names],{'attributes':['type','selection']})
 stage='currency inspection'
 company=call('res.users','read',[[uid]],{'fields':['company_id']})[0]['company_id'][0]
 currency=call('res.company','read',[[company]],{'fields':['currency_id']})[0]['currency_id'][0]
 currency_name=call('res.currency','read',[[currency]],{'fields':['name']})[0]['name'];report['company_currency']=currency_name
 if currency_name!='EGP':raise RuntimeError('Company currency is not EGP. No global currency changes made; user direction is required.')
 stage='permission configuration inspection'
 def xid(module,name):
  rows=call('ir.model.data','search_read',[[['module','=',module],['name','=',name]]],{'fields':['res_id'],'limit':1})
  if not rows:raise RuntimeError('Required standard permission group unavailable.')
  return rows[0]['res_id']
 groups=[xid('base','group_user'),xid('sales_team','group_sale_salesman'),xid('base','group_partner_manager')]
 user_fields=fields('res.users',['group_ids','groups_id','company_id','company_ids'])
 group_field='group_ids' if 'group_ids' in user_fields else 'groups_id'
 stage='reviewer credentials and creation'
 existing=call('res.users','search_read',[[['login','=',LOGIN]]],{'fields':['name'],'limit':1})
 reviewer_password=get_password(SERVICE,LOGIN)
 if existing:
  if existing[0]['name']!='2S Assessment Reviewer' or not reviewer_password:raise RuntimeError('Reviewer login already exists without the expected local Keychain credential; it was not reset.')
  reviewer=existing[0]['id'];report['account_created']=False
  call('res.users','write',[[reviewer],{group_field:[[6,0,groups]]}])
 else:
  reviewer_password=secrets.token_urlsafe(30)
  set_password(SERVICE,LOGIN,reviewer_password)
  reviewer=call('res.users','create',[{'name':'2S Assessment Reviewer','login':LOGIN,'email':LOGIN,'password':reviewer_password,group_field:[[6,0,groups]],'company_id':company,'company_ids':[[6,0,[company]]]}])
  report['account_created']=True
 report['reviewer_id']=reviewer
 reviewer_uid=common.authenticate(DB,LOGIN,reviewer_password,{})
 if reviewer_uid!=reviewer:raise RuntimeError('Reviewer XML-RPC authentication failed.')
 def review(model,method,args,kw=None):return proxy.execute_kw(DB,reviewer_uid,reviewer_password,model,method,args,dict(kw or {},context=context))
 report['xmlrpc_authentication']='passed'
 report['internal_user']=review('res.users','has_group',[[reviewer_uid],'base.group_user'])
 report['administrator']=review('res.users','has_group',[[reviewer_uid],'base.group_system'])
 report['access_rights_administrator']=review('res.users','has_group',[[reviewer_uid],'base.group_erp_manager'])
 if not report['internal_user'] or report['administrator'] or report['access_rights_administrator']:raise RuntimeError('Reviewer privilege validation failed.')
 report['requested_groups']=['base.group_user','sales_team.group_sale_salesman (own documents)','base.group_partner_manager (Contacts edit access)']
 stage='create synthetic demo records'
 # Reuse only IDs explicitly recorded by this setup; never discover/update real records by name.
 prior={}
 if (root/'docs/reviewer_setup.json').exists():
  prior=json.loads((root/'docs/reviewer_setup.json').read_text())
 customer=prior.get('customer_id')
 if customer:
  rows=call('res.partner','read',[[customer]],{'fields':['name','email']})
  if not rows or rows[0]['name']!='2S Demo Customer' or rows[0]['email']!='demo.customer@example.com':raise RuntimeError('Previously recorded demo customer identity changed; no existing record modified.')
 else:customer=call('res.partner','create',[{'name':'2S Demo Customer','phone':'01012345678','city':'Cairo','email':'demo.customer@example.com','customer_rank':1}])
 report['customer_id']=customer
 product=prior.get('product_id')
 if not product:
  product_fields=fields('product.product',['type','taxes_id','tax_ids','is_storable'])
  values={'name':'2S Demo Cotton T-Shirt','list_price':450.0,'sale_ok':True}
  selection=dict(product_fields.get('type',{}).get('selection',[]))
  if 'consu' in selection:values['type']='consu'
  elif 'product' in selection:values['type']='product'
  if 'is_storable' in product_fields:values['is_storable']=False
  for tax in ['taxes_id','tax_ids']:
   if tax in product_fields:values[tax]=[[6,0,[]]]
  product=call('product.product','create',[values])
 report['product_id']=product
 line_fields=fields('sale.order.line',['tax_id','tax_ids'])
 def quotation():
  line={'name':'2S Demo Cotton T-Shirt','product_id':product,'product_uom_qty':1.0,'price_unit':450.0}
  for tax in ['tax_id','tax_ids']:
   if tax in line_fields:line[tax]=[[6,0,[]]]
  return call('sale.order','create',[{'partner_id':customer,'user_id':reviewer,'company_id':company,'order_line':[[0,0,line]]}])
 main=prior.get('quotation_id')
 if main:
  rows=call('sale.order','read',[[main]],{'fields':['state','partner_id']})
  if not rows or rows[0]['partner_id'][0]!=customer:raise RuntimeError('Recorded quotation identity changed; no order modified.')
  if rows[0]['state']!='draft':main=None
 if not main:main=quotation()
 report['quotation_id']=main
 stage='verify reviewer customer and phone access'
 rows=review('res.partner','search_read',[[['id','=',customer],['customer_rank','>',0]]],{'fields':['name','phone','city','email'],'limit':1})
 if not rows:raise RuntimeError('Reviewer cannot see the synthetic customer.')
 report['customer_visibility']='passed'
 if not review('res.partner','write',[[customer],{'phone':'01012345678'}]):raise RuntimeError('Reviewer phone write was not acknowledged.')
 if review('res.partner','read',[[customer]],{'fields':['phone']})[0]['phone']!='01012345678':raise RuntimeError('Reviewer phone readback mismatch.')
 report['phone_write_readback']='passed'
 stage='verify reviewer Sales and line access'
 orders=review('sale.order','search_read',[[['id','=',main]]],{'fields':['name','state','amount_total','currency_id','partner_id'],'limit':1})
 if not orders or orders[0]['state']!='draft' or orders[0]['amount_total']!=450.0 or orders[0]['currency_id'][0]!=currency:raise RuntimeError('Main quotation visibility, currency or total validation failed.')
 report['quotation_number']=orders[0]['name'];report['quotation_total']=450.0;report['quotation_state']='draft';report['sales_visibility']='passed'
 lines=review('sale.order.line','search_read',[[['order_id','=',main],['display_type','=',False]]],{'fields':['product_uom_qty','price_unit','price_subtotal']})
 if len(lines)!=1 or lines[0]['product_uom_qty']!=1 or lines[0]['price_subtotal']!=450.0:raise RuntimeError('Reviewer order line validation failed.')
 report['order_details']='passed'
 stage='verify confirmation using separate synthetic quotation'
 secondary=quotation();review('sale.order','action_confirm',[[secondary]])
 if review('sale.order','read',[[secondary]],{'fields':['state']})[0]['state']!='sale':raise RuntimeError('Reviewer confirmation readback failed.')
 report['confirmation_permission']='passed'
 call('sale.order','action_cancel',[[secondary]]);call('sale.order','unlink',[[secondary]]);secondary=None;report['confirmation_test_cleanup']='passed'
 if review('sale.order','read',[[main]],{'fields':['state']})[0]['state']!='draft':raise RuntimeError('Main review quotation is no longer draft.')
 report['main_quotation_remains_draft']=True
 report['password_location']='macOS login Keychain: 2S Sales Hub Odoo Reviewer (not in repository)'
 report['status']='passed'
except RuntimeError as e:
 report['status']='blocked';report['failure_stage']=stage;report['message']=str(e)
except xmlrpc.client.Fault as e:
 report['status']='failed';report['failure_stage']=stage
 report['fault_category']='permission' if e.faultCode in (3,4) or 'AccessError' in e.faultString or 'AccessDenied' in e.faultString else 'validation_or_schema'
 report['schema_mentions']=[v for v in ['group_ids','groups_id','tax_id','tax_ids','Invalid field','Expected singleton'] if v in e.faultString]
except Exception as e:
 report['status']='failed';report['failure_stage']=stage;report['failure_type']=type(e).__name__
finally:
 if secondary:
  try:call('sale.order','action_cancel',[[secondary]]);call('sale.order','unlink',[[secondary]]);report['confirmation_test_cleanup']='passed'
  except Exception:report['confirmation_cleanup_order_id']=secondary
 (root/'docs/reviewer_setup.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(report,indent=2));print('No passwords were printed or saved to source. Retrieve the reviewer password in macOS Keychain Access if setup passed.')
 input('Press Return to close.')
