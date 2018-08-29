/**
 * Pony Outstream Helper Library
 * Copyright (c) 2018 - Stewart Gebbie. Licensed under the MIT licence.
 * vim: set ts=2 sw=0:
 */

actor OutStreamNop is OutStream
	"""
	An output stream that does nothing.
	"""

  be write(data: ByteSeq) => None
  be print(data: ByteSeq) => None
  be printv(data: ByteSeqIter) => None
  be writev(data: ByteSeqIter) => None

actor OutStreamString is OutStream
	"""
	An outstream alternative that accumulates to a string.
	
	This additionally has `access()` methods for setting up observers
	that trip if the predicate evaluates to true.
	"""

	let _text: String ref

	let _tee: (OutStream | None)

	var _check: {ref (String ref):Bool} ref
	var _timeout: {ref (String)} iso
	var _count: U32
	var _max: U32

	new create(tee': (OutStream|None) = None) =>
		_tee = tee'
		_text = recover ref String(4000) end // start with a larger buffer
		_check = {ref (s:String ref): Bool => true} iso
		_timeout = {ref (s:String) => None} iso
		_count = 0
		_max = 0

	// -- update

  be write(data: ByteSeq) => _write(data); _retry()
  be print(data: ByteSeq) => this.>_write(data).>_write("\n"); _retry()
  be printv(data: ByteSeqIter) => for s in data.values() do _write(s) end; _write("\n"); _retry()
  be writev(data: ByteSeqIter) => for s in data.values() do _write(s) end; _retry()

	// note, in order to ensure correct ordering use 'fun _write' internally
	// rather than calling 'be write' via a message send.
  fun ref _write(data: ByteSeq) =>
		_text.append(data)
		match _tee
		| (let tee: OutStream) => tee.write(data)
		end

	// -- access

	be access(f: {ref (String)} iso) =>
		access_ref_val_iso(consume f)

	be access_ref_val_iso(f: {ref (String)} iso) =>
		f(_text.clone())

	be access_ref_ref_iso(f: {ref (String ref)} iso) =>
		let ff:{ref (String ref)} ref = recover ref consume f end
		ff(_text)

	be access_iso_iso_iso(f: {iso (String iso)} iso) =>
		let t: String iso = _text.clone()
		(consume f)(consume t)

	be access_retry(max: U32
			, predicate: {ref (String ref):Bool} iso
			, timeout: {ref (String)} iso = {ref (s:String) => None} iso
			, count: U32 = 0) =>
			// note, continual s.contains("abc") calls can be very expensive
		_check = consume predicate
		_timeout = consume timeout
		_count = 0
		_max = max
		_retry()

	fun ref _retry() =>
		if _max > 0 then
			if (not _check(_text)) then
				if _count < _max then
					_count = _count + 1
				else
					_timeout(_text.clone())
					_reset()
				end
			end
		end

	fun ref _reset() =>
		_check = {ref (s:String ref): Bool => true} iso
		_timeout = {ref (s:String) => None} iso
		_count = 0
		_max = 0
