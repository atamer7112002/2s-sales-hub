"""Real Online demo verification; credentials stay in memory, synthetic records only."""
import getpass,json,socket,uuid,xmlrpc.client
from pathlib import Path
socket.setdefaulttimeout(30)
url='https://2s-sales-demo.odoo.com';db='2s-sales-demo'
report={}; ids={}
def save():
 Path(__file__).resolve().parents[1].joinpath('docs/sales_verification.json').write_text(json.dumps(report,indent=2)+'\n')
try:
 login=getpass.getpass('Odoo login (hidden): ');password=getpass.getpass('Local Odoo password (hidden): ')
 uid=xmlrpc.client.ServerProxy(url+'/xmlrpc/2/common').authenticate(db,login,password,{})
 if not uid: raise RuntimeError('Authentication rejected')
 proxy=xmlrpc.client.ServerProxy(url+'/xmlrpc/2/object')
 def call(model,method,args,kw=None):return proxy.execute_kw(db,uid,password,model,method,args,kw or {})
 report['authentication']='passed'
 report['internal_user']=call('res.users','has_group',[[uid],'base.group_user'])
 orders=call('sale.order','search_read',[[]],{'fields':['id','state'],'limit':5})
 report['order_retrieval']='passed';report['order_sample_count']=len(orders)
 tag='2S API verification '+uuid.uuid4().hex[:8]
 ids['partner']=call('res.partner','create',[{'name':tag,'customer_rank':1}])
 assert call('res.partner','write',[[ids['partner']],{'phone':'+20 100 000 0000'}])
 assert call('res.partner','read',[[ids['partner']]],{'fields':['phone']})[0]['phone']=='+20 100 000 0000'
 report['phone_write_readback']='passed'
 ids['product']=call('product.product','create',[{'name':tag,'list_price':100.0}])
 ids['order']=call('sale.order','create',[{'partner_id':ids['partner'],'order_line':[[0,0,{'product_id':ids['product'],'product_uom_qty':2,'price_unit':100.0}]]}])
 lines=call('sale.order.line','search_read',[[['order_id','=',ids['order']]]],{'fields':['product_uom_qty','price_unit','price_subtotal']})
 assert lines and lines[0]['product_uom_qty']==2
 report['order_lines']='passed'
 call('sale.order','action_confirm',[[ids['order']]])
 assert call('sale.order','read',[[ids['order']]],{'fields':['state']})[0]['state']=='sale'
 report['confirmation_readback']='passed'
except Exception as e:
 report['failure_type']=type(e).__name__;print('Verification failed; raw error suppressed.')
 if isinstance(e,xmlrpc.client.Fault):
  report['failure_category']='access' if 'AccessError' in e.faultString else 'validation' if 'ValidationError' in e.faultString else 'method_or_schema'
  report['fault_mentions']=[v for v in ['has_group','product_uom_qty','sale.order','customer_rank','Expected singleton','Invalid field'] if v in e.faultString]
finally:
 for key,model in [('order','sale.order'),('product','product.product'),('partner','res.partner')]:
  if key in ids:
   try:
    if key=='order':call(model,'action_cancel',[[ids[key]]])
    call(model,'unlink',[[ids[key]]]);report[key+'_cleanup']='passed'
   except Exception:report[key+'_cleanup']='failed';report[key+'_cleanup_id']=ids[key]
 save();print(json.dumps(report,indent=2));input('Press Return to close.')
