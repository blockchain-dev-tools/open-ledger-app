use std::ffi::CString;
use std::os::raw::c_char;
use std::ptr;

use open_ledger_biz::errors::ChainError;

/// FFI 返回值结构体。
/// success=true → data 指向 hex 结果字符串
/// success=false → error_code 和 error_msg 描述错误
#[repr(C)]
pub struct FfiResult {
    pub data: *mut c_char,
    pub error_code: i32,
    pub error_msg: *mut c_char,
}

impl FfiResult {
    pub fn ok(data: String) -> Self {
        FfiResult {
            data: CString::new(data).map(|cs| cs.into_raw()).unwrap_or(ptr::null_mut()),
            error_code: 0,
            error_msg: ptr::null_mut(),
        }
    }

    pub fn ok_hex(data: &[u8]) -> Self {
        Self::ok(hex::encode(data))
    }

    pub fn err(code: i32, msg: String) -> Self {
        FfiResult {
            data: ptr::null_mut(),
            error_code: code,
            error_msg: CString::new(msg).map(|cs| cs.into_raw()).unwrap_or(ptr::null_mut()),
        }
    }

    pub fn from_chain_error(e: ChainError) -> Self {
        let code = error_code(&e);
        let msg = e.to_string();
        Self::err(code, msg)
    }

    pub fn into_ptr(self) -> *mut FfiResult {
        Box::into_raw(Box::new(self))
    }
}

/// 释放 FfiResult 内部的内存（data 和 error_msg）。
#[no_mangle]
pub unsafe extern "C" fn free_ffi_result(r: *mut FfiResult) {
    if !r.is_null() {
        let result = Box::from_raw(r);
        if !result.data.is_null() {
            let _ = CString::from_raw(result.data);
        }
        if !result.error_msg.is_null() {
            let _ = CString::from_raw(result.error_msg);
        }
    }
}

/// ChainError → 错误码映射。
fn error_code(e: &ChainError) -> i32 {
    match e {
        ChainError::InvalidPath(_) => 1,
        ChainError::DerivationFailed(_) => 2,
        ChainError::InvalidMnemonic(_) => 3,
        ChainError::EnigmaError(_) => 4,
        ChainError::ParseError(_) => 5,
        ChainError::InvalidPrivateKey(_) => 6,
        ChainError::AddressError(_) => 7,
        ChainError::CryptoError(_) => 100,
    }
}
