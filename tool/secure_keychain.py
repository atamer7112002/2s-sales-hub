"""macOS Keychain access without secret-bearing subprocess arguments or logging."""
import ctypes
from ctypes import c_void_p,c_uint32,c_int32,c_char_p,byref
sec=ctypes.CDLL('/System/Library/Frameworks/Security.framework/Security')
cf=ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
sec.SecKeychainFindGenericPassword.argtypes=[c_void_p,c_uint32,c_char_p,c_uint32,c_char_p,ctypes.POINTER(c_uint32),ctypes.POINTER(c_void_p),ctypes.POINTER(c_void_p)]
sec.SecKeychainFindGenericPassword.restype=c_int32
sec.SecKeychainAddGenericPassword.argtypes=[c_void_p,c_uint32,c_char_p,c_uint32,c_char_p,c_uint32,c_void_p,ctypes.POINTER(c_void_p)]
sec.SecKeychainAddGenericPassword.restype=c_int32
sec.SecKeychainItemModifyAttributesAndData.argtypes=[c_void_p,c_void_p,c_uint32,c_void_p]
sec.SecKeychainItemModifyAttributesAndData.restype=c_int32
sec.SecKeychainItemFreeContent.argtypes=[c_void_p,c_void_p]
cf.CFRelease.argtypes=[c_void_p]
def _find(service,account):
 s,a=service.encode(),account.encode();length=c_uint32();data=c_void_p();item=c_void_p()
 status=sec.SecKeychainFindGenericPassword(None,len(s),s,len(a),a,byref(length),byref(data),byref(item))
 if status==-25300:return None,None
 if status:raise RuntimeError('Keychain access failed; unlock the login keychain and permit local Python access.')
 try:value=ctypes.string_at(data,length.value).decode()
 finally:sec.SecKeychainItemFreeContent(None,data)
 return value,item
def get_password(service,account):
 value,item=_find(service,account)
 if item:cf.CFRelease(item)
 return value
def set_password(service,account,password):
 _,item=_find(service,account);value=password.encode();s,a=service.encode(),account.encode()
 try:
  if item:status=sec.SecKeychainItemModifyAttributesAndData(item,None,len(value),value)
  else:status=sec.SecKeychainAddGenericPassword(None,len(s),s,len(a),a,len(value),value,None)
  if status:raise RuntimeError('Could not save the reviewer password in Keychain; no password was logged.')
 finally:
  if item:cf.CFRelease(item)
