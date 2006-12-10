''	FreeBASIC - 32-bit BASIC Compiler.
''	Copyright (C) 2004-2007 The FreeBASIC development team.
''
''	This program is free software; you can redistribute it and/or modify
''	it under the terms of the GNU General Public License as published by
''	the Free Software Foundation; either version 2 of the License, or
''	(at your option) any later version.
''
''	This program is distributed in the hope that it will be useful,
''	but WITHOUT ANY WARRANTY; without even the implied warranty of
''	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
''	GNU General Public License for more details.
''
''	You should have received a copy of the GNU General Public License
''	along with this program; if not, write to the Free Software
''	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA.


'' intermediate representation - virtual registers and three-address-codes management
''
'' obs: 1) the 3-addr-codes are optimized to 2-address, what helps generating better
''         code for CISC, but that will make porting to other CPUs (r-i-g-h-t) hard to do
''		2) operand 2 is never loaded if it's an immediate or variable, again
''         'cause the CISC arch, where every (almost) operation accepts an imm/var src
''      3) stream is flushed on any LABEL, JUMP or CALL emited, as there's no CFG
''         (Control-Flow-Graph), so the optimizations are only done inside each block
''      4) when the 3-addr-code stream is flushed, it's first sent to DAG, where
''         common sub-expressions inside the basic block are eliminated and virtual regs
''         are re-assigned; when the DAG returns, the code is converted to machine-code
''
'' chng: sep/2004 written [v1ctor]


#include once "inc\fb.bi"
#include once "inc\fbint.bi"
#include once "inc\reg.bi"
#include once "inc\emit.bi"
#include once "inc\emitdbg.bi"
#include once "inc\flist.bi"
#include once "inc\ir.bi"


type IR_CTX
	tacTB			as TFLIST
	taccnt			as integer
	tacidx			as IRTAC ptr

	vregTB			as TFLIST
end type

declare sub hFlushUOP _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval vr as IRVREG ptr _
	)

declare sub hFlushBOP _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval v2 as IRVREG ptr, _
		byval vr as IRVREG ptr _
	)

declare sub hFlushCOMP _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval v2 as IRVREG ptr, _
		byval vr as IRVREG ptr, _
		byval label as FBSYMBOL ptr _
	)

declare sub hFlushSTORE _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval v2 as IRVREG ptr _
	)

declare sub hFlushLOAD _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval vr as IRVREG ptr _
	)

declare sub hFlushCONVERT _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval v2 as IRVREG ptr _
	)

declare sub hFlushCALL _
	( _
		byval op as integer, _
		byval proc as FBSYMBOL ptr, _
		byval bytestopop as integer, _
		byval v1 as IRVREG ptr, _
		byval vr as IRVREG ptr _
	)

declare sub hFlushBRANCH _
	( _
		byval op as integer, _
		byval label as FBSYMBOL ptr _
	)

declare sub hFlushSTACK _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval ex as integer _
	)

declare sub hFlushADDR _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval vr as IRVREG ptr _
	)

declare sub hFlushMEM _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval v2 as IRVREG ptr, _
		byval bytes as integer, _
		byval extra as any ptr _
	)

declare sub hFreeIDX _
	( _
		byval vreg as IRVREG ptr, _
		byval force as integer = FALSE _
	)

declare sub hFreeREG _
	( _
		byval vreg as IRVREG ptr, _
		byval force as integer = FALSE _
	)

declare sub hCreateTMPVAR _
	( _
		byval vreg as IRVREG ptr _
	)

declare sub hFreePreservedRegs _
	( _
 		_
	)

declare sub irDump _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval v2 as IRVREG ptr, _
		byval vr as IRVREG ptr _
	)

'' globals
	dim shared ir as IR_CTX

	dim shared regTB(0 to EMIT_REGCLASSES-1) as REGCLASS ptr

'':::::
sub irInit
	dim as integer i

	''
	ir.tacidx = NULL
	ir.taccnt = 0

	flistNew( @ir.tacTB, IR_INITADDRNODES, len( IRTAC ) )

	''
	flistNew( @ir.vregTB, IR_INITVREGNODES, len( IRVREG ) )

	''
	emitInit( )

	for i = 0 to EMIT_REGCLASSES-1
		regTB(i) = emitGetRegClass( i )
	next i


end sub

'':::::
sub irEnd

	''
	flistFree( @ir.vregTB )

	''
	flistFree( @ir.tacTB )

	ir.tacidx = NULL
	ir.taccnt = 0

end sub

'':::::
private sub hLoadIDX( byval vreg as IRVREG ptr )
    dim as IRVREG ptr vi

	if( vreg = NULL ) then
		exit sub
	end if

	select case vreg->typ
	case IR_VREGTYPE_IDX, IR_VREGTYPE_PTR
	case else
		exit sub
	end select

	'' any vreg attached?
	vi = vreg->vidx
	if( vi = NULL ) then
		exit sub
	end if

	'' x86 assumption: don't load immediates to registers
	if( vi->typ = IR_VREGTYPE_IMM ) then
		exit sub
	end if

	regTB(FB_DATACLASS_INTEGER)->ensure( regTB(FB_DATACLASS_INTEGER), _
										 vi, _
										 symbGetDataSize( FB_DATATYPE_INTEGER ) )

end sub

'':::::
#macro hGetVREG( vreg, dt, dc, t )
	if( vreg <> NULL ) then
		t = vreg->typ

		dt = vreg->dtype
		if( dt >= FB_DATATYPE_POINTER ) then
			dt = FB_DATATYPE_UINT
			dc = FB_DATACLASS_INTEGER
		else
			dc = symb_dtypeTB(dt).class
		end if

	else
		t  = INVALID
		dt = INVALID
		dc = INVALID
	end if
#endmacro

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

''::::
private sub hRelink _
	( _
		byval vreg as IRVREG ptr, _
		byval tvreg as IRTACVREG ptr _
	) static

	if( vreg->tacvhead = NULL ) then
		vreg->tacvhead = tvreg
	else
		vreg->tacvtail->next = tvreg
	end if

	vreg->tacvtail = tvreg

end sub

#macro hRelinkVreg(v,t)
    t->v.reg.pParent = NULL
    t->v.reg.next = NULL

    if( v <> NULL ) then
    	hRelink( v, @t->v.reg )
    	v->taclast = t

    	if( v->vidx <> NULL ) then
    		t->v.idx.vreg = v->vidx
    		t->v.idx.pParent = @v->vidx
    		t->v.idx.next = NULL
    		hRelink( v->vidx, @t->v.idx )
    		v->vidx->taclast = t
    	end if

    	if( v->vaux <> NULL ) then
    		t->v.aux.vreg = v->vaux
    		t->v.aux.pParent = @v->vaux
    		t->v.aux.next = NULL
    		hRelink( v->vaux, @t->v.aux )
    		v->vaux->taclast = t
    	end if
    end if
#endmacro

'':::::
sub irEmit _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval v2 as IRVREG ptr, _
		byval vr as IRVREG ptr, _
		byval ex1 as FBSYMBOL ptr = NULL, _
		byval ex2 as integer = 0 _
	) static

    dim as IRTAC ptr t

    t = flistNewItem( @ir.tacTB )

    t->pos = ir.taccnt

    t->op = op

    t->v1.reg.vreg = v1
    hRelinkVreg( v1, t )

    t->v2.reg.vreg = v2
    hRelinkVreg( v2, t )

    t->vr.reg.vreg = vr
    hRelinkVreg( vr, t )

    t->ex1 = ex1
    t->ex2 = ex2

    ir.taccnt += 1

end sub

'':::::
sub irEmitCONVERT _
	( _
		byval v1 as IRVREG ptr, _
		byval dtype1 as integer, _
		byval v2 as IRVREG ptr, _
		byval dtype2 as integer _
	) static

	if( dtype1 > FB_DATATYPE_POINTER ) then
		dtype1 = FB_DATATYPE_POINTER
	end if

	select case symb_dtypeTB(dtype1).class
	case FB_DATACLASS_INTEGER
		irEmit( AST_OP_TOINT, v1, v2, NULL )
	case FB_DATACLASS_FPOINT
		irEmit( AST_OP_TOFLT, v1, v2, NULL )
	end select

end sub

'':::::
sub irEmitLABEL _
	( _
		byval label as FBSYMBOL ptr _
	) static

	irFlush( )

	emitLABEL( label )

end sub

'':::::
sub irEmitRETURN _
	( _
		byval bytestopop as integer _
	) static

	irFlush( )

	emitRET( bytestopop )

end sub

'':::::
sub irProcBegin _
	( _
		byval proc as FBSYMBOL ptr _
	) static

	emitProcBegin( proc )

	edbgProcBegin( proc )

end sub

'':::::
sub irProcEnd _
	( _
		byval proc as FBSYMBOL ptr _
	) static

	emitProcEnd( proc )

	edbgProcEnd( proc )

end sub

'':::::
sub irEmitPROCBEGIN _
	( _
		byval proc as FBSYMBOL ptr, _
		byval initlabel as FBSYMBOL ptr _
	) static

	dim as integer class_

    irFlush( )

	'' clear regs so they aren't different from one proc to another
	for class_ = 0 to EMIT_REGCLASSES-1
		regTB(class_)->Clear( regTB(class_) )
	next

	emitPROCHEADER( proc, initlabel )

end sub

'':::::
sub irEmitPROCEND _
	( _
		byval proc as FBSYMBOL ptr, _
		byval initlabel as FBSYMBOL ptr, _
		byval exitlabel as FBSYMBOL ptr _
	) static

    dim as integer bytestopop, mode

    irFlush( )

    mode = symbGetProcMode( proc )
    if( (mode = FB_FUNCMODE_CDECL) or _
    	((mode = FB_FUNCMODE_STDCALL) and (env.clopt.nostdcall)) ) then
		bytestopop = 0
	else
		bytestopop = symbGetProcParamsLen( proc )
	end if

	emitPROCFOOTER( proc, bytestopop, initlabel, exitlabel )

end sub

'':::::
sub irScopeBegin _
	( _
		byval s as FBSYMBOL ptr _
	) static

	edbgScopeBegin( s )

end sub

'':::::
sub irScopeEnd _
	( _
		byval s as FBSYMBOL ptr _
	) static

	edbgScopeEnd( s )

end sub

'':::::
sub irEmitPUSHARG _
	( _
		byval vr as IRVREG ptr, _
		byval plen as integer _
	) static

	if( plen = 0 ) then
		irEmitPUSH( vr )
	else
		irEmitPUSHUDT( vr, plen )
	end if

end sub

'':::::
sub irEmitASM _
	( _
		byval text as zstring ptr _
	) static

	irFlush( )

	emitASM( text )

end sub

'':::::
sub irEmitCOMMENT _
	( _
		byval text as zstring ptr _
	) static

	emitCOMMENT( text )

end sub

''::::
sub irEmitJMPTB _
	( _
		byval dtype as integer, _
		byval label as FBSYMBOL ptr _
	) static

	irFlush( )

	emitJMPTB( dtype, symbGetMangledName( label ) )

end sub

''::::
sub irEmitDBG _
	( _
		byval proc as FBSYMBOL ptr, _
		byval op as integer, _
		byval ex as integer _
	) static

	irFlush( )

	select case as const op
	case AST_OP_DBG_LINEINI
		edbgLineBegin( proc, ex )
	case AST_OP_DBG_LINEEND
		edbgLineEnd( proc, ex )

	case AST_OP_DBG_SCOPEINI
		edbgEmitScopeINI( cast( FBSYMBOL ptr, ex ) )
	case AST_OP_DBG_SCOPEEND
		edbgEmitScopeEND( cast( FBSYMBOL ptr, ex ) )
	end select

end sub

'':::::
sub irEmitVARINIBEGIN _
	( _
		byval sym as FBSYMBOL ptr _
	) static

	'' no flush, all var-ini go to data sections

	emitVARINIBEGIN( sym )

end sub

'':::::
sub irEmitVARINIEND _
	( _
		byval sym as FBSYMBOL ptr _
	) static

	emitVARINIEND( sym )

end sub

'':::::
sub irEmitVARINIi _
	( _
		byval dtype as integer, _
		byval value as integer _
	) static

	emitVARINIi( dtype, value )

end sub

'':::::
sub irEmitVARINIf _
	( _
		byval dtype as integer, _
		byval value as double _
	) static

	emitVARINIf( dtype, value )

end sub

'':::::
sub irEmitVARINI64 _
	( _
		byval dtype as integer, _
		byval value as longint _
	) static

	emitVARINI64( dtype, value )

end sub

'':::::
sub irEmitVARINIOFS _
	( _
		byval sym as FBSYMBOL ptr, _
		byval ofs as integer _
	) static

	emitVARINIOFS( symbGetMangledName( sym ), ofs )

end sub

'':::::
sub irEmitVARINISTR _
	( _
		byval totlgt as integer, _
		byval litstr as zstring ptr, _
		byval litlgt as integer _
	) static

	dim as zstring ptr s

	'' zstring * 1?
	if( totlgt = 0 ) then
		emitVARINIi( FB_DATATYPE_BYTE, 0 )
		exit sub
	end if

	''
	if( litlgt > totlgt ) then
		errReportWarn( FB_WARNINGMSG_LITSTRINGTOOBIG )
		'' !!!FIXME!!! truncate will fail if it lies on an escape seq
		s = hEscape( left( *litstr, totlgt ) )
	else
		s = hEscape( litstr )
	end if

	''
	emitVARINISTR( s )

	if( litlgt < totlgt ) then
		emitVARINIPAD( totlgt - litlgt )
	end if

end sub

'':::::
sub irEmitVARINIWSTR _
	( _
		byval totlgt as integer, _
		byval litstr as wstring ptr, _
		byval litlgt as integer _
	) static

	dim as zstring ptr s
	dim as integer wclen

	'' wstring * 1?
	if( totlgt = 0 ) then
		emitVARINIi( env.target.wchar.type, 0 )
		exit sub
	end if

	''
	if( litlgt > totlgt ) then
		errReportWarn( FB_WARNINGMSG_LITSTRINGTOOBIG )
		'' !!!FIXME!!! truncate will fail if it lies on an escape seq
		s = hEscapeW( left( *litstr, totlgt ) )
	else
		s = hEscapeW( litstr )
	end if

	''
	wclen = symbGetDataSize( FB_DATATYPE_WCHAR )

	emitVARINIWSTR( s )

	if( litlgt < totlgt ) then
		emitVARINIPAD( (totlgt - litlgt) * wclen )
	end if

end sub

'':::::
sub irEmitVARINIPAD _
	( _
		byval bytes as integer _
	) static

	emitVARINIPAD( bytes )

end sub

'':::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
function irNewVR _
	( _
		byval dtype as integer, _
		byval vtype as integer _
	) as IRVREG ptr static

	dim as IRVREG ptr v

	if( dtype > FB_DATATYPE_POINTER ) then
		dtype = FB_DATATYPE_POINTER
	end if

	v = flistNewItem( @ir.vregTB )

	v->typ = vtype
	v->dtype = dtype
	v->sym = NULL
	v->reg = INVALID
	v->vidx	= NULL
	v->vaux	= NULL
	v->ofs = 0

	v->tacvhead = NULL
	v->tacvtail = NULL
	v->taclast = NULL

	function = v

end function

'':::::
function irAllocVREG _
	( _
		byval dtype as integer _
	) as IRVREG ptr static

	dim as IRVREG ptr vr

	vr = irNewVR( dtype, IR_VREGTYPE_REG )

	function = vr

	'' longint?
	if( ISLONGINT( dtype ) ) then
		 vr->vaux = irNewVR( FB_DATATYPE_INTEGER, IR_VREGTYPE_REG )
	end if

end function

'':::::
function irAllocVRIMM _
	( _
		byval dtype as integer, _
		byval value as integer _
	) as IRVREG ptr static

	dim as IRVREG ptr vr

	vr = irNewVR( dtype, IR_VREGTYPE_IMM )

	function = vr

	vr->value = value

	'' longint?
	if( ISLONGINT( dtype ) ) then
		 vr->vaux = irNewVR( FB_DATATYPE_INTEGER, IR_VREGTYPE_IMM )
		 vr->vaux->value = 0
	end if

end function

'':::::
function irAllocVRIMM64 _
	( _
		byval dtype as integer, _
		byval value as longint _
	) as IRVREG ptr static

	dim as IRVREG ptr vr

	vr = irNewVR( dtype, IR_VREGTYPE_IMM )

	function = vr

	vr->value = cuint( value )

	'' aux
	vr->vaux = irNewVR( FB_DATATYPE_INTEGER, IR_VREGTYPE_IMM )

	vr->vaux->value = cint( value shr 32 )

end function

'':::::
function irAllocVRVAR _
	( _
		byval dtype as integer, _
		byval symbol as FBSYMBOL ptr, _
		byval ofs as integer _
	) as IRVREG ptr static

	dim as IRVREG ptr vr, va

	vr = irNewVR( dtype, IR_VREGTYPE_VAR )

	function = vr

	vr->sym = symbol
	vr->ofs = ofs

	'' longint?
	if( ISLONGINT( dtype ) ) then
		va = irNewVR( FB_DATATYPE_INTEGER, IR_VREGTYPE_VAR )
		vr->vaux = va
		va->ofs = ofs + FB_INTEGERSIZE
	end if

end function

'':::::
function irAllocVRIDX _
	( _
		byval dtype as integer, _
		byval symbol as FBSYMBOL ptr, _
		byval ofs as integer, _
		byval mult as integer, _
		byval vidx as IRVREG ptr _
	) as IRVREG ptr static

	dim as IRVREG ptr vr, va

	vr = irNewVR( dtype, IR_VREGTYPE_IDX )

	function = vr

	vr->sym = symbol
	vr->ofs = ofs
	vr->mult = mult
	vr->vidx = vidx

	'' longint?
	if( ISLONGINT( dtype ) ) then
		va = irNewVR( FB_DATATYPE_INTEGER, IR_VREGTYPE_IDX )
		vr->vaux= va
		va->ofs = ofs + FB_INTEGERSIZE
	end if

end function

'':::::
function irAllocVRPTR _
	( _
		byval dtype as integer, _
		byval ofs as integer, _
		byval vidx as IRVREG ptr _
	) as IRVREG ptr static

	dim as IRVREG ptr vr, va

	vr = irNewVR( dtype, IR_VREGTYPE_PTR )

	function = vr

	vr->ofs = ofs
	vr->mult = 1
	vr->vidx = vidx

	'' longint?
	if( ISLONGINT( dtype ) ) then
		va = irNewVR( FB_DATATYPE_INTEGER, IR_VREGTYPE_IDX )
		vr->vaux= va
		va->ofs = ofs + FB_INTEGERSIZE
	end if

end function

'':::::
function irAllocVROFS _
	( _
		byval dtype as integer, _
		byval symbol as FBSYMBOL ptr, _
		byval ofs as integer _
	) as IRVREG ptr static

	dim as IRVREG ptr vr

	vr = irNewVR( dtype, IR_VREGTYPE_OFS )

	function = vr

	vr->sym = symbol
	vr->ofs = ofs

end function

'':::::
function irGetVRDataClass _
	( _
		byval vreg as IRVREG ptr _
	) as integer static

	dim as integer dtype

	dtype = vreg->dtype

	if( dtype > FB_DATATYPE_POINTER ) then
		dtype = FB_DATATYPE_POINTER
	end if

	function = symb_dtypeTB(dtype).class

end function

'':::::
function irGetVRDataSize _
	( _
		byval vreg as IRVREG ptr _
	) as integer static

	dim as integer dtype

	dtype = vreg->dtype

	if( dtype > FB_DATATYPE_POINTER ) then
		dtype = FB_DATATYPE_POINTER
	end if

	function = symb_dtypeTB(dtype).size

end function

'':::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
private sub hRename _
	( _
		byval vold as IRVREG ptr, _
		byval vnew as IRVREG ptr _
	) static

    dim as IRTACVREG ptr t
    dim as IRVREG ptr v

	'' reassign tac table vregs
	'' (assuming res, v1 and v2 will never point to the same vreg!)
	t = vold->tacvhead
	do
		'' if it's an index or auxiliary vreg, update parent
		if( t->pParent <> NULL ) then
			*t->pParent = vnew
		end if
		t->vreg = vnew
		t = t->next
	loop while( t <> NULL )

	vnew->tacvhead = vold->tacvhead
	vnew->tacvtail = vold->tacvtail
	vnew->taclast = vold->taclast

end sub

'':::::
private sub hReuse _
	( _
		byval t as IRTAC ptr _
	) static

    dim as IRVREG ptr v1, v2, vr
    dim as integer v1_dtype, v1_dclass, v1_typ
    dim as integer v2_dtype, v2_dclass, v2_typ
    dim as integer vr_dtype, vr_dclass, vr_typ
    dim as integer op, v1rename, v2rename
    dim as IRTACVREG ptr tmp

	op	 = t->op
	v1   = t->v1.reg.vreg
	v2   = t->v2.reg.vreg
	vr   = t->vr.reg.vreg

	hGetVREG( v1, v1_dtype, v1_dclass, v1_typ )
	hGetVREG( v2, v2_dtype, v2_dclass, v2_typ )
    hGetVREG( vr, vr_dtype, vr_dclass, vr_typ )

	select case astGetOpClass( op )
	case AST_NODECLASS_UOP
		if( vr <> v1 ) then
			if( vr_dtype = v1_dtype ) then
           		if( irGetDistance( v1 ) = IR_MAXDIST ) then
           			hRename( vr, v1 )
           		end if
           	end if
		end if

	case AST_NODECLASS_BOP, AST_NODECLASS_COMP

		if( vr = NULL ) then
			exit sub
		end if

		'' check if operands have the same class (can happen 'cause the x86 FPU hacks)
		if( v1_dclass <> v2_dclass ) then
			exit sub
		end if

		v1rename = FALSE
		if( vr <> v1 ) then
			if( vr_dtype = v1_dtype ) then
           		if( irGetDistance( v1 ) = IR_MAXDIST ) then
           			v1rename = TRUE
           		end if
           	end if
		end if

		v2rename = FALSE
		if( astGetOpIsCommutative( op ) ) then
			if( vr <> v2 ) then
				if( vr_dtype = v2_dtype ) then
					if( v2_typ <> IR_VREGTYPE_IMM ) then
           				if( irGetDistance( v2 ) = IR_MAXDIST ) then
           					v2rename = TRUE
           				end if
           			end if
           		end if
			end if
		end if

		if( v1rename and v2rename ) then
			if( irIsREG( v1 ) = FALSE ) then
           		v1rename = FALSE
			end if
		end if

		if( v1rename ) then
           	hRename( vr, v1 )

		elseif( v2rename ) then
		 	swap t->v1, t->v2

			hRename( vr, v2 )
		end if

	end select

end sub

'':::::
sub irFlush static
    dim as integer op
    dim as IRTAC ptr t
    dim as IRVREG ptr v1, v2, vr

	if( ir.taccnt = 0 ) then
		exit sub
	end if

	'hOptimize

	t = flistGetHead( @ir.tacTB )
	do
		ir.tacidx = t

		hReuse( t )

		op = t->op
		v1 = t->v1.reg.vreg
		v2 = t->v2.reg.vreg
		vr = t->vr.reg.vreg

		''
		'irDump( op, v1, v2, vr )

        ''
		select case as const astGetOpClass( op )
		case AST_NODECLASS_UOP
			hFlushUOP( op, v1, vr )

		case AST_NODECLASS_BOP
			hFlushBOP( op, v1, v2, vr )

		case AST_NODECLASS_COMP
			hFlushCOMP( op, v1, v2, vr, t->ex1 )

		case AST_NODECLASS_ASSIGN
			hFlushSTORE( op, v1, v2 )

		case AST_NODECLASS_LOAD
			hFlushLOAD( op, v1, vr )

		case AST_NODECLASS_CONV
			hFlushCONVERT( op, v1, v2 )

		case AST_NODECLASS_STACK
			hFlushSTACK( op, v1, t->ex2 )

		case AST_NODECLASS_CALL
			hFlushCALL( op, t->ex1, t->ex2, v1, vr )

		case AST_NODECLASS_BRANCH
			hFlushBRANCH( op, t->ex1 )

		case AST_NODECLASS_ADDR
			hFlushADDR( op, v1, vr )

		case AST_NODECLASS_MEM
			hFlushMEM( op, v1, v2, t->ex2, t->ex1 )

		end select

		t = flistGetNext( t )
	loop while( t <> NULL )

	''
	ir.tacidx = NULL
	ir.taccnt = 0
	flistReset( @ir.tacTB )

	''
	flistReset( @ir.vregTB )

    ''
    hFreePreservedRegs( )

end sub

'':::::
private sub hFlushBRANCH _
	( _
		byval op as integer, _
		byval label as FBSYMBOL ptr _
	) static

	''
	select case as const op
	case AST_OP_LABEL
		emitLABEL( label )

	case AST_OP_JMP
		emitJUMP( label )

	case AST_OP_CALL
		emitCALL( label, 0 )

	case AST_OP_RET
		emitRET( 0 )

	case else
		emitBRANCH( op, label )
	end select

end sub

'':::::
private sub hFreePreservedRegs( ) static
    dim as integer class_, reg

	'' for each reg class
	for class_ = 0 to EMIT_REGCLASSES-1

		'' for each register on that class
		reg = regTB(class_)->getFirst( regTB(class_) )
		do until( reg = INVALID )
			'' if not free
			if( regTB(class_)->isFree( regTB(class_), reg ) = FALSE ) then

        		assert( emitIsRegPreserved( class_, reg ) )

        		'' free reg
        		regTB(class_)->free( regTB(class_), reg )

			end if

        	'' next reg
        	reg = regTB(class_)->getNext( regTB(class_), reg )
		loop

	next

end sub

'':::::
private sub hPreserveRegs _
	( _
		byval ptrvreg as IRVREG ptr = NULL _
	) static

    dim as integer class_

	'' for each reg class
	for class_ = 0 to EMIT_REGCLASSES-1

    	'' set the register that shouldn't be preserved (used for CALLPTR only)
    	dim as integer npreg

    	npreg = INVALID
    	if( class_ = FB_DATACLASS_INTEGER ) then
    		if( ptrvreg <> NULL ) then

    			select case ptrvreg->typ
    			case IR_VREGTYPE_REG
    				npreg = ptrvreg->reg

    			case IR_VREGTYPE_IDX, IR_VREGTYPE_PTR
    				ptrvreg = ptrvreg->vidx
    				if( ptrvreg <> NULL ) then
    					npreg = ptrvreg->reg
    				end if
    			end select

    			ptrvreg = NULL
    		end if
    	end if

		'' for each register on that class
    	dim as integer reg

		reg = regTB(class_)->getFirst( regTB(class_) )
		do until( reg = INVALID )
			'' if not free
			if( (regTB(class_)->isFree( regTB(class_), reg ) = FALSE) and _
				(reg <> npreg) ) then

    			dim as IRVREG ptr vr
    			dim as integer vr_dclass, vr_dtype, vr_typ

				'' get the attached vreg
				vr = regTB(class_)->getVreg( regTB(class_), reg )
                assert( vr <> NULL )

                hGetVREG( vr, vr_dtype, vr_dclass, vr_typ )

        		'' if reg is not preserved between calls
        		if( emitIsRegPreserved( vr_dclass, reg ) = FALSE ) then
    				dim as integer freg

        			'' find a preserved reg to copy to
        			freg = emitGetFreePreservedReg( vr_dclass, vr_dtype )

        			'' if none free, spill reg
        			if( freg = INVALID ) then
        				irStoreVR( vr, reg )

        			'' else, copy it to a preserved reg
        			else
    					dim as IRVREG tr

        				tr = *vr
        				vr->reg = regTB(vr_dclass)->allocateReg( regTB(vr_dclass), freg, vr )
        				emitMOV( vr, @tr )

        			end if

        			'' free reg
        			regTB(vr_dclass)->free( regTB(vr_dclass), reg )
        		end if
        	end if

        	'' next reg
        	reg = regTB(class_)->getNext( regTB(class_), reg )
		loop

	next

end sub

'':::::
private sub hFlushCALL _
	( _
		byval op as integer, _
		byval proc as FBSYMBOL ptr, _
		byval bytestopop as integer, _
		byval v1 as IRVREG ptr, _
		byval vr as IRVREG ptr _
	) static

    dim as integer mode
    dim as integer vr_dclass, vr_dtype, vr_typ, vr_reg, vr_reg2
    dim as IRVREG ptr va

	'' call function
    if( proc <> NULL ) then
    	mode = symbGetProcMode( proc )
    	if( (mode = FB_FUNCMODE_CDECL) or _
    		((mode = FB_FUNCMODE_STDCALL) and (env.clopt.nostdcall)) ) then
			if( bytestopop = 0 ) then
				bytestopop = symbGetProcParamsLen( proc )
			end if
		else
			bytestopop = 0
		end if

    	'' save used registers and free the FPU stack
    	hPreserveRegs( )

		emitCALL( proc, bytestopop )

	'' call or jump to pointer
	else

    	'' if it's a CALL, save used registers and free the FPU stack
    	if( op = AST_OP_CALLPTR ) then
    		hPreserveRegs( v1 )
    	end if

		'' load pointer
		hGetVREG( v1, vr_dtype, vr_dclass, vr_typ )
		hLoadIDX( v1 )
		if( vr_typ = IR_VREGTYPE_REG ) then
			regTB(vr_dclass)->ensure( regTB(vr_dclass), _
									  v1, _
									  symbGetDataSize( vr_dtype ) )
		end if

		'' CALLPTR
		if( op = AST_OP_CALLPTR ) then
			emitCALLPTR( v1, bytestopop )
		'' JUMPPTR
		else
			emitJUMPPTR( v1 )
		end if

		'' free pointer
		hFreeREG( v1 )
	end if

	'' load result
	if( vr <> NULL ) then
		hGetVREG( vr, vr_dtype, vr_dclass, vr_typ )

		emitGetResultReg( vr_dtype, vr_dclass, vr_reg, vr_reg2 )

		'' longints..
		if( ISLONGINT( vr_dtype ) ) then
			va = vr->vaux
			va->reg = regTB(vr_dclass)->allocateReg( regTB(vr_dclass), vr_reg2, va )
			va->typ = IR_VREGTYPE_REG
		end if

		vr->reg = regTB(vr_dclass)->allocateReg( regTB(vr_dclass), vr_reg, vr )
		vr->typ = IR_VREGTYPE_REG

    	'' fb allows function calls w/o saving the result
		hFreeREG( vr )
	end if

end sub

'':::::
private sub hFlushSTACK _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval ex as integer _
	) static

	dim as integer v1_typ, v1_dtype, v1_dclass
	dim as IRVREG ptr va

	''
	if( op = AST_OP_STACKALIGN ) then
		emitSTACKALIGN( ex )
		exit sub
	end if

	''
	hGetVREG( v1, v1_dtype, v1_dclass, v1_typ )

	hLoadIDX( v1 )

	'' load only if it's a reg (x86 assumption)
	if( v1_typ = IR_VREGTYPE_REG ) then
		'' handle longint
		if( ISLONGINT( v1_dtype ) ) then
			va = v1->vaux
			regTB(v1_dclass)->ensure( regTB(v1_dclass), _
									  va, _
									  symbGetDataSize( FB_DATATYPE_INTEGER ), _
									  FALSE )

			v1_dtype = FB_DATATYPE_INTEGER
		end if

		regTB(v1_dclass)->ensure( regTB(v1_dclass), _
								  v1, _
								  symbGetDataSize( v1_dtype ) )
	end if

	''
	select case op
	case AST_OP_PUSH
		emitPUSH( v1 )
	case AST_OP_PUSHUDT
		emitPUSHUDT( v1, ex )
	case AST_OP_POP
		emitPOP( v1 )
	end select

    ''
	hFreeREG( v1 )

end sub

'':::::
private sub hFlushUOP _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval vr as IRVREG ptr _
	) static

	dim as integer v1_typ, v1_dtype, v1_dclass
	dim as integer vr_typ, vr_dtype, vr_dclass
	dim as IRVREG ptr va

	''
	hGetVREG( v1, v1_dtype, v1_dclass, v1_typ )
	hGetVREG( vr, vr_dtype, vr_dclass, vr_typ )

	hLoadIDX( v1 )
	hLoadIDX( vr )

    ''
    if ( vr <> NULL ) then
		if( v1 <> vr ) then
			'' handle longint
			if( ISLONGINT( vr_dtype ) ) then
				va = vr->vaux
				regTB(vr_dclass)->ensure( regTB(vr_dclass), _
										  va, _
										  symbGetDataSize( FB_DATATYPE_INTEGER ), _
										  FALSE )

				vr_dtype = FB_DATATYPE_INTEGER
			end if

			regTB(vr_dclass)->ensure( regTB(vr_dclass), _
									  vr, _
									  symbGetDataSize( vr_dtype ) )
		end if
	end if

	'' UOP to self? x86 assumption at AST
	if( vr <> NULL ) then
		'' handle longint
		if( ISLONGINT( v1_dtype ) ) then
			va = v1->vaux
			regTB(v1_dclass)->ensure( regTB(v1_dclass), _
									  va, _
									  symbGetDataSize( FB_DATATYPE_INTEGER ), _
									  FALSE )

			v1_dtype = FB_DATATYPE_INTEGER
		end if

		regTB(v1_dclass)->ensure( regTB(v1_dclass), _
								  v1, _
								  symbGetDataSize( v1_dtype ) )
	end if

	''
	select case as const op
	case AST_OP_NEG
		emitNEG( v1 )
	case AST_OP_NOT
		emitNOT( v1 )

	case AST_OP_ABS
		emitABS( v1 )
	case AST_OP_SGN
		emitSGN( v1 )

	case AST_OP_SIN
		emitSIN( v1 )
	case AST_OP_ASIN
		emitASIN( v1 )
	case AST_OP_COS
		emitCOS( v1 )
	case AST_OP_ACOS
		emitACOS( v1 )
	case AST_OP_TAN
		emitTAN( v1 )
	case AST_OP_ATAN
		emitATAN( v1 )
	case AST_OP_SQRT
		emitSQRT( v1 )
	case AST_OP_LOG
		emitLOG( v1 )
	case AST_OP_FLOOR
		emitFLOOR( v1 )
	end select

    ''
    if ( vr <> NULL ) then
		if( v1 <> vr ) then
			emitMOV( vr, v1 )
		end if
	end if

    ''
	hFreeREG( v1 )
	hFreeREG( vr )

end sub

'':::::
private sub hFlushBOP _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval v2 as IRVREG ptr, _
		byval vr as IRVREG ptr _
	) static

	dim as integer v1_typ, v1_dtype, v1_dclass
	dim as integer v2_typ, v2_dtype, v2_dclass
	dim as integer vr_typ, vr_dtype, vr_dclass
	dim as IRVREG ptr va

	''
	hGetVREG( v1, v1_dtype, v1_dclass, v1_typ )
	hGetVREG( v2, v2_dtype, v2_dclass, v2_typ )
	hGetVREG( vr, vr_dtype, vr_dclass, vr_typ )

	hLoadIDX( v1 )
	hLoadIDX( v2 )
	hLoadIDX( vr )

	'' BOP to self? (x86 assumption at AST)
	if( vr = NULL ) then
		if( v2_typ <> IR_VREGTYPE_IMM ) then		'' x86 assumption
			'' handle longint
			if( ISLONGINT( v2_dtype ) ) then
				va = v2->vaux
				regTB(v2_dclass)->ensure( regTB(v2_dclass), _
										  va, _
										  symbGetDataSize( FB_DATATYPE_INTEGER ), _
										  FALSE )

				v2_dtype = FB_DATATYPE_INTEGER
			end if

			regTB(v2_dclass)->ensure( regTB(v2_dclass), _
									  v2, _
									  symbGetDataSize( v2_dtype ) )
		end if

	else
		if( v2_typ = IR_VREGTYPE_REG ) then			'' x86 assumption
			'' handle longint
			if( ISLONGINT( v2_dtype ) ) then
				va = v2->vaux
				regTB(v2_dclass)->ensure( regTB(v2_dclass), _
										  va, _
										  symbGetDataSize( FB_DATATYPE_INTEGER ), _
										  FALSE )

				v2_dtype = FB_DATATYPE_INTEGER
			end if

			regTB(v2_dclass)->ensure( regTB(v2_dclass), _
									  v2, _
									  symbGetDataSize( v2_dtype ) )
		end if

		'' destine allocation comes *after* source, 'cause the x86 FPU stack
		'' handle longint
		if( ISLONGINT( v1_dtype ) ) then
			va = v1->vaux
			regTB(v1_dclass)->ensure( regTB(v1_dclass), _
									  va, _
									  symbGetDataSize( FB_DATATYPE_INTEGER ), _
									  FALSE )

			v1_dtype = FB_DATATYPE_INTEGER
		end if

		regTB(v1_dclass)->ensure( regTB(v1_dclass), _
								  v1, _
								  symbGetDataSize( v1_dtype ) )
	end if

    ''
	select case as const op
	case AST_OP_ADD
		emitADD( v1, v2 )
	case AST_OP_SUB
		emitSUB( v1, v2 )
	case AST_OP_MUL
		emitMUL( v1, v2 )
	case AST_OP_DIV
        emitDIV( v1, v2 )
	case AST_OP_INTDIV
        emitINTDIV( v1, v2 )
	case AST_OP_MOD
		emitMOD( v1, v2 )

	case AST_OP_SHL
		emitSHL( v1, v2 )
	case AST_OP_SHR
		emitSHR( v1, v2 )

	case AST_OP_AND
		emitAND( v1, v2 )
	case AST_OP_OR
		emitOR( v1, v2 )
	case AST_OP_XOR
		emitXOR( v1, v2 )
	case AST_OP_EQV
		emitEQV( v1, v2 )
	case AST_OP_IMP
		emitIMP( v1, v2 )

	case AST_OP_ATAN2
        emitATN2( v1, v2 )
    case AST_OP_POW
    	emitPOW( v1, v2 )
	end select

    '' not BOP to self?
	if ( vr <> NULL ) then
		'' result not equal destine? (can happen with DAG optimizations)
		if( (v1 <> vr) ) then
			'' handle longint
			if( ISLONGINT( vr_dtype ) ) then
				va = vr->vaux
				regTB(vr_dclass)->ensure( regTB(vr_dclass), _
										  va, _
										  symbGetDataSize( FB_DATATYPE_INTEGER ), _
										  FALSE )

				vr_dtype = FB_DATATYPE_INTEGER
			end if

			regTB(vr_dclass)->ensure( regTB(vr_dclass), _
									  vr, _
									  symbGetDataSize( vr_dtype ) )

			emitMOV( vr, v1 )
		end if
	end if

    ''
	hFreeREG( v1 )
	hFreeREG( v2 )
	hFreeREG( vr )

end sub

'':::::
private sub hFlushCOMP _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval v2 as IRVREG ptr, _
		byval vr as IRVREG ptr, _
		byval label as FBSYMBOL ptr _
	) static

	dim as string lname
	dim as integer v1_typ, v1_dtype, v1_dclass
	dim as integer v2_typ, v2_dtype, v2_dclass
	dim as integer vr_typ, vr_dtype, vr_dclass
	dim as IRVREG ptr va
	dim as integer doload

	''
	hGetVREG( v1, v1_dtype, v1_dclass, v1_typ )
	hGetVREG( v2, v2_dtype, v2_dclass, v2_typ )
	hGetVREG( vr, vr_dtype, vr_dclass, vr_typ )

	hLoadIDX( v1 )
	hLoadIDX( v2 )
	hLoadIDX( vr )

	'' load source if it's a reg, or if result was not allocated
	doload = FALSE
	if( vr = NULL ) then							'' x86 assumption
		if( v2_dclass = FB_DATACLASS_INTEGER ) then	'' /
			if( v2_typ <> IR_VREGTYPE_IMM ) then	'' /
				if( v1_dclass <> FB_DATACLASS_FPOINT ) then
					doload = TRUE
				end if
			end if
		end if
	end if

	if( (v2_typ = IR_VREGTYPE_REG) or doload ) then
		'' handle longint
		if( ISLONGINT( v2_dtype ) ) then
			va = v2->vaux
			regTB(v2_dclass)->ensure( regTB(v2_dclass), _
									  va, _
									  symbGetDataSize( FB_DATATYPE_INTEGER ), _
									  FALSE )

			v2_dtype = FB_DATATYPE_INTEGER
		end if

		regTB(v2_dclass)->ensure( regTB(v2_dclass), _
								  v2, _
								  symbGetDataSize( v2_dtype ) )
		v2_typ = IR_VREGTYPE_REG
	end if

	'' destine allocation comes *after* source, 'cause the FPU stack
	doload = FALSE
	if( (vr <> NULL) and (vr = v1) ) then			'' x86 assumption
		doload = TRUE
	elseif( v1_dclass = FB_DATACLASS_FPOINT ) then	'' /
		doload = TRUE
	elseif( v1_typ = IR_VREGTYPE_IMM) then          '' /
		doload = TRUE
	elseif( v2_typ <> IR_VREGTYPE_REG ) then        '' /
		if( v2_typ <> IR_VREGTYPE_IMM ) then
			doload = TRUE
		end if
	end if

	if( (v1_typ = IR_VREGTYPE_REG) or doload ) then
		'' handle longint
		if( ISLONGINT( v1_dtype ) ) then
			va = v1->vaux
			regTB(v1_dclass)->ensure( regTB(v1_dclass), _
									  va, _
									  symbGetDataSize( FB_DATATYPE_INTEGER ), _
									  FALSE )

			v1_dtype = FB_DATATYPE_INTEGER
		end if

		regTB(v1_dclass)->ensure( regTB(v1_dclass), _
								  v1, _
								  symbGetDataSize( v1_dtype ) )
	end if

	'' result not equal destine? (can happen with DAG optimizations and floats comparations)
	if( vr <> NULL ) then
		if( vr <> v1 ) then
			vr->reg = regTB(vr_dclass)->allocate( regTB(vr_dclass), _
												  vr, _
												  symbGetDataSize( vr_dtype ) )
			vr->typ = IR_VREGTYPE_REG
		end if
	end if

	''
	select case as const op
	case AST_OP_EQ
		emitEQ( vr, label, v1, v2 )
	case AST_OP_NE
		emitNE( vr, label, v1, v2 )
	case AST_OP_GT
		emitGT( vr, label, v1, v2 )
	case AST_OP_LT
		emitLT( vr, label, v1, v2 )
	case AST_OP_LE
		emitLE( vr, label, v1, v2 )
	case AST_OP_GE
		emitGE( vr, label, v1, v2 )
	end select

    ''
	hFreeREG( v1 )
	hFreeREG( v2 )
	if( vr <> NULL ) then
		hFreeREG( vr )
	end if

end sub

'':::::
private sub hSpillRegs( ) static
    dim as IRVREG ptr vr
    dim as integer reg
    dim as integer class_

	'' for each reg class
	for class_ = 0 to EMIT_REGCLASSES-1

		'' for each register on that class
		reg = regTB(class_)->getFirst( regTB(class_) )
		do until( reg = INVALID )
			'' if not free
			if( regTB(class_)->isFree( regTB(class_), reg ) = FALSE ) then

				'' get the attached vreg
				vr = regTB(class_)->getVreg( regTB(class_), reg )

        		'' spill
        		irStoreVR( vr, reg )

        		'' free reg
        		regTB(class_)->free( regTB(class_), reg )
        	end if

        	'' next reg
        	reg = regTB(class_)->getNext( regTB(class_), reg )
		loop

	next

end sub

'':::::
private sub hFlushSTORE _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval v2 as IRVREG ptr _
	) static

	dim as integer v1_typ, v1_dtype, v1_dclass
	dim as integer v2_typ, v2_dtype, v2_dclass
	dim as IRVREG ptr va

	''
	if( op = AST_OP_SPILLREGS ) then
		hSpillRegs( )
		exit sub
	end if

	''
	hGetVREG( v1, v1_dtype, v1_dclass, v1_typ )
	hGetVREG( v2, v2_dtype, v2_dclass, v2_typ )

	hLoadIDX( v1 )
	hLoadIDX( v2 )

    '' if dst is a fpoint, only load src if its a reg (x86 assumption)
	if( (v2_typ = IR_VREGTYPE_REG) or _
		((v2_typ <> IR_VREGTYPE_IMM) and (v1_dclass = FB_DATACLASS_INTEGER)) ) then

		'' handle longint
		if( ISLONGINT( v2_dtype ) ) then
			va = v2->vaux
			regTB(v2_dclass)->ensure( regTB(v2_dclass), _
									  va, _
									  symbGetDataSize( FB_DATATYPE_INTEGER ), _
									  FALSE )

			v2_dtype = FB_DATATYPE_INTEGER
		end if

		regTB(v2_dclass)->ensure( regTB(v2_dclass), _
								  v2, _
								  symbGetDataSize( v2_dtype ) )
	end if

	''
	emitSTORE( v1, v2 )

    ''
	hFreeREG( v1 )
	hFreeREG( v2 )

end sub

'':::::
private sub hFlushLOAD _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval vr as IRVREG ptr _
	) static

	dim as integer v1_typ, v1_dtype, v1_dclass, v1_reg
	dim as IRVREG ptr va

	''
	hGetVREG( v1, v1_dtype, v1_dclass, v1_typ )

	hLoadIDX( v1 )

	''
	select case op
	case AST_OP_LOAD
		'' handle longint
		if( ISLONGINT( v1_dtype ) ) then
			va = v1->vaux
			regTB(v1_dclass)->ensure( regTB(v1_dclass), _
									  va, _
									  symbGetDataSize( FB_DATATYPE_INTEGER ), _
									  FALSE )

			v1_dtype = FB_DATATYPE_INTEGER
		end if

		regTB(v1_dclass)->ensure( regTB(v1_dclass), _
								  v1, _
								  symbGetDataSize( v1_dtype ) )

	case AST_OP_LOADRES
		if( v1_typ = IR_VREGTYPE_REG ) then
			'' handle longint
			if( ISLONGINT( v1_dtype ) ) then
				va = v1->vaux
				regTB(v1_dclass)->ensure( regTB(v1_dclass), _
										  va, _
										  symbGetDataSize( FB_DATATYPE_INTEGER ), _
										  FALSE )

				'' can't change v1_dtype
				v1_reg = regTB(v1_dclass)->ensure( regTB(v1_dclass), _
												   v1, _
												   symbGetDataSize( FB_DATATYPE_INTEGER ) )

			else
				v1_reg = regTB(v1_dclass)->ensure( regTB(v1_dclass), _
												   v1, _
												   symbGetDataSize( v1_dtype ) )
			end if


		else
			v1_reg = INVALID
		end if

		dim as integer vr_reg, vr_reg2

		emitGetResultReg( v1_dtype, v1_dclass, vr_reg, vr_reg2 )

		if( vr_reg <> v1_reg ) then
			'' handle longint
			if( ISLONGINT( v1_dtype ) ) then
				va = vr->vaux
				va->reg = regTB(v1_dclass)->allocateReg( regTB(v1_dclass), vr_reg2, va )
				va->typ = IR_VREGTYPE_REG
			end if

			vr->reg = regTB(v1_dclass)->allocateReg( regTB(v1_dclass), vr_reg, vr )
			vr->typ = IR_VREGTYPE_REG

			''
			emitLOAD( vr, v1 )

			''
			hFreeREG( vr )						'' assuming this is the last operation
		end if
    end select

	''
	hFreeREG( v1 )

end sub

'':::::
private sub hFlushCONVERT _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval v2 as IRVREG ptr _
	) static

	dim as integer v1_typ, v1_dtype, v1_dclass
	dim as integer v2_typ, v2_dtype, v2_dclass
	dim as integer reuse
	dim as IRVREG ptr va

	''
	hGetVREG( v1, v1_dtype, v1_dclass, v1_typ )
	hGetVREG( v2, v2_dtype, v2_dclass, v2_typ )

	hLoadIDX( v1 )
	hLoadIDX( v2 )

    '' x86 assumption: if src is a reg and if classes are the same and
    ''                 src won't be used (DAG?), reuse src
	reuse = FALSE
	if( (v1_dclass = v2_dclass) and (v2_typ = IR_VREGTYPE_REG) ) then

		'' fp to fp conversion with source already on stack? do nothing..
		if( v2_dclass = FB_DATACLASS_FPOINT ) then
			v1->reg = v2->reg
			v2->reg = INVALID
			v1->typ = IR_VREGTYPE_REG
			regTB(v1_dclass)->setOwner( regTB(v1_dclass), v1->reg, v1 )
			exit sub
		end if

		'' it's an integer, check if used again
		if( irGetDistance( v2 ) = IR_MAXDIST ) then
			'' don't reuse if any operand is a byte (because [E]SI/[E]DI) or longint
			select case symbGetDataSize( v1_dtype )
			case 1, FB_INTEGERSIZE*2

			case else
				select case symbGetDataSize( v2_dtype )
				case 1, FB_INTEGERSIZE*2

				case else
					reuse = TRUE
				end select
			end select
		end if
	end if

	if( reuse ) then
		v1->reg = v2->reg
		v1->typ = IR_VREGTYPE_REG
		regTB(v1_dclass)->setOwner( regTB(v1_dclass), v1->reg, v1 )

	else
		if( v2_typ = IR_VREGTYPE_REG ) then			'' x86 assumption
			'' handle longint
			if( ISLONGINT( v2_dtype ) ) then
				va = v2->vaux
				regTB(v2_dclass)->ensure( regTB(v2_dclass), _
										  va, _
										  symbGetDataSize( FB_DATATYPE_INTEGER ), _
										  FALSE )

				v2_dtype = FB_DATATYPE_INTEGER
			end if

			regTB(v2_dclass)->ensure( regTB(v2_dclass), _
									  v2, _
									  symbGetDataSize( v2_dtype ) )
		end if

		'' handle longint
		if( ISLONGINT( v1_dtype ) ) then
			va = v1->vaux
			va->reg = regTB(v1_dclass)->allocate( regTB(v1_dclass), _
												  va, _
												  symbGetDataSize( FB_DATATYPE_INTEGER ) )
			va->typ = IR_VREGTYPE_REG

			v1_dtype = FB_DATATYPE_INTEGER
		end if

		v1->reg = regTB(v1_dclass)->allocate( regTB(v1_dclass), _
											  v1, _
											  symbGetDataSize( v1_dtype ) )
		v1->typ = IR_VREGTYPE_REG
	end if

	''
	emitLOAD( v1, v2 )

	''
	if( reuse = FALSE ) then
		hFreeREG( v2 )
	else
		v2->reg = INVALID
	end if

	''
	hFreeREG( v1 )

end sub

'':::::
private sub hFlushADDR _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval vr as IRVREG ptr _
	) static

	dim as integer v1_typ, v1_dtype, v1_dclass
	dim as integer vr_typ, vr_dtype, vr_dclass

	''
	hGetVREG( v1, v1_dtype, v1_dclass, v1_typ )
	hGetVREG( vr, vr_dtype, vr_dclass, vr_typ )

	hLoadIDX( v1 )
	hLoadIDX( vr )

	''
	if( v1_typ = IR_VREGTYPE_REG ) then				'' x86 assumption
		regTB(v1_dclass)->ensure( regTB(v1_dclass), _
								  v1, _
								  symbGetDataSize( v1_dtype ) )
	end if

	if( vr_typ = IR_VREGTYPE_REG ) then             '' x86 assumption
		regTB(vr_dclass)->ensure( regTB(vr_dclass), _
								  vr, _
								  symbGetDataSize( vr_dtype ) )
	end if

	''
	select case op
	case AST_OP_ADDROF
		emitADDROF( vr, v1 )
	case AST_OP_DEREF
		emitDEREF( vr, v1 )
	end select

    ''
	hFreeREG( v1 )
	hFreeREG( vr )

end sub

'':::::
private sub hFlushMEM _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval v2 as IRVREG ptr, _
		byval bytes as integer, _
		byval extra as any ptr _
	) static

	''
	hLoadIDX( v1 )
	hLoadIDX( v2 )

	''
	select case as const op
	case AST_OP_MEMMOVE
		emitMEMMOVE( v1, v2, bytes )

	case AST_OP_MEMSWAP
		emitMEMSWAP( v1, v2, bytes )

	case AST_OP_MEMCLEAR
		emitMEMCLEAR( v1, bytes )

	case AST_OP_STKCLEAR
		emitSTKCLEAR( bytes, cint( extra ) )
	end select

    ''
	hFreeREG( v1 )
	hFreeREG( v2 )

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
private sub hFreeIDX _
	( _
		byval vreg as IRVREG ptr, _
		byval force as integer = FALSE _
	)

	dim as IRVREG ptr vidx

	if( vreg = NULL ) then
		exit sub
	end if

	vidx = vreg->vidx
    if( vidx <> NULL ) then
    	if( vidx->reg <> INVALID ) then
    		hFreeREG( vidx, force )				'' recursively
    		vreg->vidx = NULL
		end if
	end if

end sub

'':::::
private sub hFreeREG _
	( _
		byval vreg as IRVREG ptr, _
		byval force as integer = FALSE _
	)

	dim as integer dclass, dist
	dim as IRVREG ptr vaux

	if( vreg = NULL ) then
		exit sub
	end if

	'' free any attached index
	hFreeIDX( vreg, force )

    ''
	if( vreg->typ <> IR_VREGTYPE_REG ) then
		exit sub
	end if

	if( vreg->reg = INVALID ) then
		exit sub
	end if

	''
	dist = IR_MAXDIST
	if( force = FALSE ) then
		dist = irGetDistance( vreg )
	end if

	if( dist = IR_MAXDIST ) then
		'' aux?
		if( vreg->vaux <> NULL ) then
			vaux = vreg->vaux
			if( vaux->reg <> INVALID ) then
				hFreeREG( vaux, TRUE )
			end if
		end if

    	dclass = irGetVRDataClass( vreg )
		regTB(dclass)->free( regTB(dclass), vreg->reg )
		vreg->reg = INVALID
	end if

end sub

'':::::
function irGetDistance _
	( _
		byval vreg as IRVREG ptr _
	) as uinteger

    dim as IRVREG ptr v
    dim as IRTAC ptr t
    dim as integer dist

	if( vreg = NULL ) then
		return IR_MAXDIST
	end if

	'' skip the current tac
	t = flistGetNext( ir.tacidx )

	'' eol?
	if( t = NULL ) then
		return IR_MAXDIST
	end if

	''
	dist = vreg->taclast->pos - t->pos

	'' not used anymore?
	if( dist < 0 ) then
		function = IR_MAXDIST
	else
		function = dist
	end if

end function

'':::::
sub irLoadVR _
	( _
		byval reg as integer, _
		byval vreg as IRVREG ptr, _
		byval doload as integer _
	) static

	dim as IRVREG rvreg

	if( vreg->typ <> IR_VREGTYPE_REG ) then

		if( doload ) then
			rvreg.typ 	= IR_VREGTYPE_REG
			rvreg.dtype = vreg->dtype
			rvreg.reg	= reg
			rvreg.vaux	= vreg->vaux

			emitLOAD( @rvreg, vreg )
		end if

    	'' free any attached reg, forcing if needed
    	hFreeIDX( vreg, TRUE )

    	vreg->typ = IR_VREGTYPE_REG
    end if

	vreg->reg = reg

end sub

'':::::
private sub hCreateTMPVAR _
	( _
		byval vreg as IRVREG ptr _
	) static

	if( vreg->typ <> IR_VREGTYPE_VAR ) then
		vreg->typ = IR_VREGTYPE_VAR
		vreg->sym = symbAddTempVar( vreg->dtype, NULL, TRUE )
		vreg->ofs = symbGetOfs( vreg->sym )
		vreg->reg = INVALID
	end if

end sub

'':::::
sub irStoreVR _
	( _
		byval vreg as IRVREG ptr, _
		byval reg as integer _
	) static

    dim as IRVREG rvreg
	dim as IRVREG ptr vareg

	if( irGetDistance( vreg ) = IR_MAXDIST ) then
		exit sub
	end if

	rvreg.typ		= IR_VREGTYPE_REG
	rvreg.dtype		= vreg->dtype
	rvreg.reg		= reg
	rvreg.vaux		= vreg->vaux

	hCreateTMPVAR( vreg )

	emitSTORE( vreg, @rvreg )

	'' handle longints
	if( ISLONGINT( vreg->dtype ) ) then
		vareg = vreg->vaux
		if( vareg->typ <> IR_VREGTYPE_VAR ) then
			regTB(FB_DATACLASS_INTEGER)->free( regTB(FB_DATACLASS_INTEGER), vareg->reg )
			vareg->reg = INVALID
			vareg->typ = IR_VREGTYPE_VAR
			vareg->ofs = vreg->ofs + FB_INTEGERSIZE
		end if
	end if

end sub

'':::::
sub irXchgTOS _
	( _
		byval reg as integer _
	) static

    dim as IRVREG rvreg

	rvreg.typ 	= IR_VREGTYPE_REG
	rvreg.dtype = FB_DATATYPE_DOUBLE
	rvreg.reg	= reg

	emitXchgTOS( @rvreg )

end sub

/'':::::
sub irDump _
	( _
		byval op as integer, _
		byval v1 as IRVREG ptr, _
		byval v2 as IRVREG ptr, _
		byval vr as IRVREG ptr _
	) static

#macro hDumpVr( id, v )
	if( v <> NULL ) then
		print " " id ":" & hex( v ) & "(" & irGetVRType( v ) & ";";
		print using "##"; irGetVRDataType( v );
		print "," & symbGetDataClass( irGetVRDataType( v ) ) & ")";
	end if
#endmacro

	if( astGetOpId( op ) <> NULL ) then
		print using "[\  \]"; *astGetOpId( op );
	else
		print using "[####]"; op;
	end if

	hDumpVr( "d", vr )
	hDumpVr( "l", v1 )
	hDumpVr( "r", v2 )

	print

end sub
'/

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

/'
'':::::
function irGetVRRealValue( byval vreg as IRVREG ptr ) as integer static
    dim as integer rval

	if( vreg = NULL ) then
		irGetVRRealValue = INVALID
		exit function
	end if

	select case as const vreg->typ
	case IR_VREGTYPE_VAR
		rval = vreg->sym

	case IR_VREGTYPE_IDX, IR_VREGTYPE_PTR
		rval = 1234

	case IR_VREGTYPE_IMM
		rval = vreg->value

	case IR_VREGTYPE_REG
		rval = vreg
	end select

	irGetVRRealValue = rval

end function

'':::::
sub irOptimize static
    dim op as integer, class as integer, i as integer, vi as integer
    dim IRVREG ptr v1, v2, vr
    dim vtx1 as integer, vtx2 as integer, vtxo as integer

	if( ir.codes = 0 ) then
		exit sub
	end if

	for i = 0 to ir.codes-1

		op 	 = tacTB(i).op
		v1   = tacTB(i).v1
		v2   = tacTB(i).v2
		vr   = tacTB(i).vr

		'class= v1->class

        ''
		select case as const astGetOpClass( op )
		'':::::
		case AST_NODECLASS_BOP

            'vtx1 = irDagGetLeaf( v1 )
            if( vtx1 = INVALID ) then
            '	vtx1 = irDagNewLeaf( v1 )
            end if

            'vtx2 = irDagGetLeaf( v2 )
            if( vtx2 = INVALID ) then
            '	vtx2 = irDagNewLeaf( v2 )
            end if

            'vtxo = irDagGetNode( op, vtx1, vtx2 )
            if( vtxo = INVALID ) then
            '	vtxo = irDagNewNode( op, vtx1, vtx2, vr )
            else
            '	irDagAddResult vtxo, vr
            end if

		'':::::
		case AST_NODECLASS_ASSIGN
            'vtx1 = irDagGetLeaf( v2 )
            if( vtx1 = INVALID ) then
            '	vtx1 = irDagNewLeaf( v2 )
            end if

            'vtxo = irDagGetNode( op, vtx1, INVALID )
            if( vtxo = INVALID ) then
            '	vtxo = irDagNewNode( op, vtx1, INVALID, v1 )
            else
            '	irDagAddResult vtxo, v1
            end if

		end select

	next i

	'dagTopSort

end sub
'/

