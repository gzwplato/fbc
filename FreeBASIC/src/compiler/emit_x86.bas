''	FreeBASIC - 32-bit BASIC Compiler.
''	Copyright (C) 2004-2006 Andre Victor T. Vicentini (av1ctor@yahoo.com.br)
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


'' code generation for x86, GNU assembler (GAS/Intel arch)
''
'' chng: sep/2004 written [v1ctor]
''  	 mar/2005 longint support added [v1ctor]


#include once "inc\fb.bi"
#include once "inc\fbint.bi"
#include once "inc\reg.bi"
#include once "inc\ir.bi"
#include once "inc\rtl.bi"
#include once "inc\emit.bi"
#include once "inc\emitdbg.bi"
#include once "inc\hash.bi"
#include once "inc\symb.bi"

type EMITDATATYPE
	class			as integer
	size			as integer
	rnametb			as integer
	mname			as zstring * 11+1
end type

''
const COMMA   = ", "


const EMIT_MAXRNAMES  = REG_MAXREGS
const EMIT_MAXRTABLES = 4				'' 8-bit, 16-bit, 32-bit, fpoint


''
declare sub 		outp				( byval s as zstring ptr )

declare sub 		hSaveAsmHeader		( )

declare function 	hGetTypeString		( byval typ as integer ) as string


''
''globals

	'' same order as EMITREG_ENUM
	dim shared rnameTB(0 to EMIT_MAXRTABLES-1, 0 to EMIT_MAXRNAMES-1) as zstring * 7+1 => _
	{ _
		{    "dl",   "di",   "si",   "cl",   "bl",   "al",   "bp",   "sp" }, _
		{    "dx",   "di",   "si",   "cx",   "bx",   "ax",   "bp",   "sp" }, _
		{   "edx",  "edi",  "esi",  "ecx",  "ebx",  "eax",  "ebp",  "esp" }, _
		{ "st(0)","st(1)","st(2)","st(3)","st(4)","st(5)","st(6)","st(7)" } _
	}

	'' same order as FB_DATATYPE
	dim shared dtypeTB(0 to FB_DATATYPES-1) as EMITDATATYPE => _
	{ _
		( FB_DATACLASS_INTEGER, 0 			    , 0, "void ptr"  ), _	'' void
		( FB_DATACLASS_INTEGER, 1			    , 0, "byte ptr"  ), _	'' byte
		( FB_DATACLASS_INTEGER, 1			    , 0, "byte ptr"  ), _	'' ubyte
		( FB_DATACLASS_INTEGER, 1               , 0, "byte ptr"  ), _	'' char
		( FB_DATACLASS_INTEGER, 2               , 1, "word ptr"  ), _	'' short
		( FB_DATACLASS_INTEGER, 2               , 1, "word ptr"  ), _	'' ushort
		( FB_DATACLASS_INTEGER, 2  				, 1, "word ptr" ), _	'' wchar
		( FB_DATACLASS_INTEGER, FB_INTEGERSIZE  , 2, "dword ptr" ), _	'' int
		( FB_DATACLASS_INTEGER, FB_INTEGERSIZE  , 2, "dword ptr" ), _   '' uint
		( FB_DATACLASS_INTEGER, FB_INTEGERSIZE  , 2, "dword ptr" ), _	'' enum
		( FB_DATACLASS_INTEGER, FB_INTEGERSIZE  , 2, "dword ptr" ), _	'' bitfield
		( FB_DATACLASS_INTEGER, FB_INTEGERSIZE*2, 2, "qword ptr" ), _	'' longint
		( FB_DATACLASS_INTEGER, FB_INTEGERSIZE*2, 2, "qword ptr" ), _	'' ulongint
		( FB_DATACLASS_FPOINT , 4			    , 3, "dword ptr" ), _	'' single
		( FB_DATACLASS_FPOINT , 8			    , 3, "qword ptr" ), _	'' double
		( FB_DATACLASS_STRING , FB_STRDESCLEN	, 0, ""          ), _	'' string
		( FB_DATACLASS_STRING , 1               , 0, "byte ptr"  ), _	'' fix-len string
		( FB_DATACLASS_INTEGER, FB_INTEGERSIZE  , 2, "dword ptr" ), _	'' struct
		( FB_DATACLASS_INTEGER, 0  				, 0, "" 		), _	'' namespace
		( FB_DATACLASS_INTEGER, FB_INTEGERSIZE  , 2, "dword ptr" ), _	'' function
		( FB_DATACLASS_INTEGER, 1			    , 0, "byte ptr"  ), _	'' fwd-ref
		( FB_DATACLASS_INTEGER, FB_INTEGERSIZE  , 2, "dword ptr" ) _	'' pointer
	}

const EMIT_MAXKEYWORDS = 600

	dim shared keywordTb(0 to EMIT_MAXKEYWORDS-1) as zstring ptr => _
	{ _
		@"st", @"cs", @"ds", @"es", @"fs", @"gs", @"ss", _
		@"mm0", @"mm1", @"mm2", @"mm3", @"mm4", @"mm5", @"mm6", @"mm7", _
		@"xmm0", @"xmm1", @"xmm2", @"xmm3", @"xmm4", @"xmm5", @"xmm6", @"xmm7", _
		@"byte", @"word", @"dword", @"qword", _
		@"ptr", @"offset", _
		@"aaa", @"aad", @"aam", @"aas", @"adc", @"add", @"addpd", @"addps", @"addsd", @"addss", @"and", @"andpd", @"andps", _
		@"andnpd", @"andnps", @"arpl", @"bound", @"bsf", @"bsr", @"bswap", @"bt", @"btc", @"btr", @"bts", @"call", @"cbw", _
		@"cwde", @"cdq", @"clc", @"cld", @"clflush", @"cli", @"clts", @"cmc", @"cmova", @"cmovae", @"cmovb", @"cmovbe", _
		@"cmovc", @"cmove", @"cmovg", @"cmovge", @"cmovl", @"cmovle", @"cmovna", @"cmovnae", @"cmovnb", @"cmovnbe", _
		@"cmovnc", @"cmovne", @"cmovng", @"cmovnge", @"cmovnl", @"cmovnle", @"cmovno", @"cmovnp", @"cmovns", @"cmovnz", _
		@"cmovo", @"cmovp", @"cmovpe", @"cmovpe", @"cmovpo", @"cmovs", @"cmovz", @"cmp", @"cmppd", @"cmpps", @"cmps", _
		@"cmpsb", @"cmpsw", @"cmpsd", @"cmpss", @"cmpxchg", @"cmpxchg8b", @"comisd", @"comiss", @"cpuid", @"cvtdq2pd", _
		@"cvtdq2ps", @"cvtpd2dq", @"cvtpd2pi", @"cvtpd2ps", @"cvtpi2pd", @"cvtpi2ps", @"cvtps2dq", @"cvtps2pd", _
		@"cvtps2pi", @"cvtsd2si", @"cvtsd2ss", @"cvtsi2sd", @"cvtsi2ss", @"cvtss2sd", @"cvtss2si", @"cvttpd2pi", _
		@"cvttpd2dq", @"cvttps2dq", @"cvttps2pi", @"cvttsd2si", @"cvttss2si", @"cwd", @"daa", @"das", @"dec", @"div", _
		@"divpd", @"divps", @"divss", @"emms", @"enter", @"f2xm1", @"fabs", @"fadd", @"faddp", @"fiadd", @"fbld", _
		@"fbstp", @"fchs", @"fclex", @"fnclex", @"fcmovb", @"fcmove", @"fcmovbe", @"fcmovu", @"fcmovnb", @"fcmovne", _
		@"fcmovnbe", @"fcmovnu", @"fcom", @"fcomp", @"fcompp", @"fcomi", @"fcomip", @"fucomi", @"fucomip", @"fcos", _
		@"fdecstp", @"fdiv", @"fdivp", @"fidiv", @"fdivr", @"fdivrp", @"fidivr", @"ffree", @"ficom", @"ficomp", _
		@"fild", @"fincstp", @"finit", @"fninit", @"fist", @"fistp", @"fld", @"fld1", @"fldl2t", @"fldl2e", @"fldpi", _
		@"fldlg2", @"fldln2", @"fldz", @"fldcw", @"fldenv", @"fmul", @"fmulp", @"fimul", @"fnop", @"fpatan", @"fprem", _
		@"fprem1", @"fptan", @"frndint", @"frstor", @"fsave", @"fnsave", @"fscale", @"fsin", @"fsincos", @"fsqrt", _
		@"fst", @"fstp", @"fstcw", @"fnstcw", @"fstenv", @"fnstenv", @"fstsw", @"fnstsw", @"fsub", @"fsubp", @"fisub", _
		@"fsubr", @"fsubrp", @"fisubr", @"ftst", @"fucom", @"fucomp", @"fucompp", @"fwait", @"fxam", @"fxch", @"fxrstor", _
		@"fxsave", @"fxtract", @"fyl2x", @"fyl2xp1", @"hlt", @"idiv", @"imul", @"in", @"inc", @"ins", @"insb", @"insw", _
		@"insd", @"int", @"into", @"invd", @"invlpg", @"iret", @"iretd", @"ja", @"jae", @"jb", @"jbe", @"jc", @"jcxz", _
		@"jecxz", @"je", @"jg", @"jge", @"jl", @"jle", @"jna", @"jnae", @"jnb", @"jnbe", @"jnc", @"jne", @"jng", @"jnge", _
		@"jnl", @"jnle", @"jno", @"jnp", @"jns", @"jnz", @"jo", @"jp", @"jpe", @"jpo", @"js", @"jz", @"jmp", @"lahf", @"lar", _
		@"ldmxcsr", @"lds", @"les", @"lfs", @"lgs", @"lss", @"lea", @"leave", @"lfence", @"lgdt", @"lidt", @"lldt", @"lmsw", _
		@"lock", @"lods", @"lodsb", @"lodsw", @"lodsd", @"loop", @"loope", @"loopz", @"loopne", @"loopnz", @"lsl", @"ltr", _
		@"maskmovdqu", @"maskmovq", @"maxpd", @"maxps", @"maxsd", @"maxss", @"mfence", @"minpd", @"minps", @"minsd", _
		@"minss", @"mov", @"movapd", @"movaps", @"movd", @"movdqa", @"movdqu", @"movdq2q", @"movhlps", @"movhpd", _
		@"movhps", @"movlhps", @"movlpd", @"movlps", @"movmskpd", @"movmskps", @"movntdq", @"movnti", @"movntpd", _
		@"movntps", @"movntq", @"movq", @"movq2dq", @"movs", @"movsb", @"movsw", @"movsd", @"movss", @"movsx", @"movupd", _
		@"movups", @"movzx", @"mul", @"mulpd", @"mulps", @"mulsd", @"mulss", @"neg", @"nop", @"not", @"or", @"orpd", _
		@"orps", @"out", @"outs", @"outsb", @"outsw", @"outsd", @"packsswb", @"packssdw", @"packuswb", @"paddb", _
		@"paddw", @"paddd", @"paddq", @"paddsb", @"paddsw", @"paddusb", @"paddusw", @"pand", @"pandn", @"pause", _
		@"pavgb", @"pavgw", @"pcmpeqb", @"pcmpeqw", @"pcmpeqd", @"pcmpgtb", @"pcmpgtw", @"pcmpgtd", @"pextrw", _
		@"pinsrw", @"pmaddwd", @"pmaxsw", @"pmaxub", @"pminsw", @"pminub", @"pmovmskb", @"pmulhuv", @"pmulhw", _
		@"pmullw", @"pmuludq", @"pop", @"popa", @"popad", @"popf", @"popfd", @"por", @"prefetcht0", @"prefetcht1", _
		@"prefetcht2", @"prefetchnta", @"psadbw", @"pshufd", @"pshufhw", @"pshuflw", @"pshufw", @"psllw", @"pslld", _
		@"psllq", @"psraw", @"psrad", @"psrldq", @"psrlw", @"psrld", @"psrlq", @"psubb", @"psubw", @"psubd", @"psubq", _
		@"psubsb", @"psubsw", @"psubusb", @"psubusw", @"punpckhbw", @"punpckhwd", @"punpckhdq", @"punpckhqdq", _
		@"punpcklbw", @"punpcklwd", @"punpckldq", @"punpcklqdq", @"push", @"pusha", @"pushad", @"pushf", @"pushfd", _
		@"pxor", @"rcl", @"rcr", @"rol", @"ror", @"rcpps", @"rcpss", @"rdmsr", @"rdpmc", @"rdtsc", @"rep", @"repe", _
		@"repz", @"repne", @"repnz", @"ret", @"rsm", @"rsqrtps", @"rsqrtss", @"sahf", @"sal", @"sar", @"shl", @"shr", _
		@"sbb", @"scas", @"scasb", @"scasw", @"scasd", @"seta", @"setae", @"setb", @"setbe", @"setc", @"sete", @"setg", _
		@"setge", @"setl", @"setle", @"setna", @"setnae", @"setnb", @"setnbe", @"setnc", @"setne", @"setng", @"setnge", _
		@"setnl", @"setnle", @"setno", @"setnp", @"setns", @"setnz", @"seto", @"setp", @"setpe", @"setpo", @"sets", _
		@"setz", @"sfence", @"sgdt", @"sidt", @"shld", @"shrd", @"shufpd", @"shufps", @"sldt", @"smsw", @"sqrtpd", _
		@"sqrtps", @"sqrtsd", @"sqrtss", @"stc", @"std", @"sti", @"stmxcsr", @"stos", @"stosb", @"stosw", @"stosd", _
		@"str", @"sub", @"subpd", @"subps", @"subsd", @"subss", @"sysenter", @"sysexit", @"test", @"ucomisd", _
		@"ucomiss", @"ud2", @"unpckhpd", @"unpckhps", @"unpcklpd", @"unpcklps", @"verr", @"verw", @"wait", @"wbinvd", _
		@"wrmsr", @"xadd", @"xchg", @"xlat", @"xlatb", @"xor", @"xorpd", @"xorps", _
		@"pavgusb", @"pfadd", @"pfsub", @"pfsubr", @"pfacc", @"pfcmpge", @"pfcmpgt", @"pfcmpeq", @"pfmin", @"pfmax", _
		@"pi2fw", @"pi2fd", @"pf2iw", @"pf2id", @"pfrcp", @"pfrsqrt", @"pfmul", @"pfrcpit1", @"pfrsqit1", @"pfrcpit2", _
		@"pmulhrw", @"pswapw", @"femms", @"prefetch", @"prefetchw", @"pfnacc", @"pfpnacc", @"pswapd", @"pmulhuw", _
		NULL _
	}


'':::::
private sub hInitKeywordsTB
    dim as integer t, i

	hashInit( )

	hashNew( @emit.keyhash, EMIT_MAXKEYWORDS )

	'' add reg names
	for t = 0 to EMIT_MAXRTABLES-1
		for i = 0 to EMIT_MAXRNAMES-1
			if( len( rnameTB(t,i) ) > 0 ) then
				hashAdd( @emit.keyhash, @rnameTB(t,i), cast( any ptr, INVALID ), INVALID )
			end if
		next
	next

	'' add asm keywords
	for i = 0 to EMIT_MAXKEYWORDS-1
		if( keywordTb(i) = NULL ) then
			exit for
		end if

		hashAdd( @emit.keyhash, keywordTb(i), cast( any ptr, INVALID ), INVALID )
	next

	emit.keyinited = TRUE

end sub

'':::::
private sub hEndKeywordsTB

	if( emit.keyinited ) then
		hashFree( @emit.keyhash )

		hashEnd( )
	end if

	emit.keyinited = FALSE

end sub

'':::::
private sub hInitRegTB
	dim as integer lastclass, regs, i

	static as integer regclass( 0 to (EMIT_REGCLASSES*EMIT_MAXRNAMES)-1 ) = _
	{ _
		FB_DATACLASS_INTEGER, _ '' edx
		FB_DATACLASS_INTEGER, _ '' edi
		FB_DATACLASS_INTEGER, _ '' esi
		FB_DATACLASS_INTEGER, _ '' ecx
		FB_DATACLASS_INTEGER, _ '' ebx
		FB_DATACLASS_INTEGER, _ '' eax
							  _ '' ebp and esp are reserved
		FB_DATACLASS_FPOINT , _ '' st(0)
		FB_DATACLASS_FPOINT , _ '' st(1)
		FB_DATACLASS_FPOINT , _ '' st(2)
		FB_DATACLASS_FPOINT , _ '' st(3)
		FB_DATACLASS_FPOINT , _ '' st(4)
		FB_DATACLASS_FPOINT , _ '' st(5)
		FB_DATACLASS_FPOINT , _ '' st(6)
		INVALID 			  _ '' no st(7) as STORE/LOAD/POW/.. need a free reg to work
	}

	''
	lastclass = INVALID
	regs = 0
	i = 0
	do
		if( lastclass <> regclass(i) ) then
			if( lastclass <> INVALID ) then
				emit.regTB(lastclass) = regNewClass( lastclass, _
								 					 regs, _
								 					 lastclass = FB_DATACLASS_FPOINT )
			end if
			regs = 0
			lastclass = regclass(i)
		end if

		if( regclass(i) = INVALID ) then
			exit do
		end if

		regs += 1
		i += 1
	loop

end sub

'':::::
private sub hEndRegTB
    dim i as integer

	for i = 0 to EMIT_REGCLASSES-1
		regDelClass( emit.regTB(i) )
	next i

end sub

'':::::
sub emitSubInit

	''
	hInitRegTB( )

	'' wchar len depends on the target platform
	dtypeTB(FB_DATATYPE_WCHAR) = dtypeTB(env.target.wchar.type)

	''
	emit.keyinited 	= FALSE

	''
	emit.dataend = 0
	emit.lastsection = INVALID

end sub

'':::::
sub emitSubEnd

	''
	hEndRegTB( )

    hEndKeywordsTB( )

end sub

'':::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
function emitGetVarName _
	( _
		byval s as FBSYMBOL ptr _
	) as string static

	dim as string sname

	if( s <> NULL ) then
		sname = *symbGetMangledName( s )

		if( symbGetOfs( s ) > 0 ) then
			sname += "+" + str( symbGetOfs( s ) )

		elseif( symbGetOfs( s ) < 0 ) then
			sname += str( symbGetOfs( s ) )
		end if

		function = sname

	else
		function = ""
	end if

end function

'':::::
function emitGetFramePtrName as zstring ptr
	static as zstring * 3+1 sname = "ebp"

	function = @sname

end function

'':::::
function emitIsRegPreserved _
	( _
		byval dclass as integer, _
		byval reg as integer _
	) as integer static

    '' fp? fpu stack *must* be cleared before calling any function
    if( dclass = FB_DATACLASS_FPOINT ) then
    	return FALSE
    end if

    select case as const reg
    case EMIT_REG_EAX, EMIT_REG_ECX, EMIT_REG_EDX
    	return FALSE
    case else
    	return TRUE
	end select

end function

'':::::
sub emitGetResultReg _
	( _
		byval dtype as integer, _
		byval dclass as integer, _
		byref r1 as integer, _
		byref r2 as integer _
	) static

	if( dtype >= FB_DATATYPE_POINTER ) then
		dtype = FB_DATATYPE_UINT
	end if

	if( dclass = FB_DATACLASS_INTEGER ) then
		r1 = EMIT_REG_EAX
		if( ISLONGINT( dtype ) ) then
			r2 = EMIT_REG_EDX
		else
			r2 = INVALID
		end if
	else
		r1 = 0							'' st(0)
		r2 = INVALID
	end if

end sub

'':::::
function emitGetFreePreservedReg _
	( _
		byval dclass as integer _
	) as integer static

	function = INVALID

	'' fp? no other regs can be used
	if( dclass = FB_DATACLASS_FPOINT ) then
		exit function
	end if

	'' try to reuse regs that are preserved between calls
	if( emit.regTB(dclass)->isFree( emit.regTB(dclass), EMIT_REG_EBX ) ) then
		function = EMIT_REG_EBX

	elseif( emit.regTB(dclass)->isFree( emit.regTB(dclass), EMIT_REG_ESI ) ) then
		function = EMIT_REG_ESI

	elseif( emit.regTB(dclass)->isFree( emit.regTB(dclass), EMIT_REG_EDI ) ) then
		function = EMIT_REG_EDI
	end if

end function

'':::::
function emitIsKeyword _
	( _
		byval text as zstring ptr _
	) as integer static

	if( emit.keyinited = FALSE ) then
		hInitKeywordsTB( )
	end if

	if( hashLookup( @emit.keyhash, text ) <> NULL ) then
		function = TRUE
	else
		function = FALSE
	end if

end function

'':::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
private function hIsRegFree _
	( _
		byval dclass as integer, _
		byval reg as integer _
	) as integer static

	'' if EBX, EDI or ESI and if they weren't ever used, return false,
	'' because hCreateFrame didn't preserve them
	if( dclass = FB_DATACLASS_INTEGER ) then
		select case reg
		case EMIT_REG_EBX, EMIT_REG_ESI, EMIT_REG_EDI
			if( EMIT_REGISUSED( FB_DATACLASS_INTEGER, reg ) = FALSE ) then
				return FALSE
			end if
		end select
	end if

	assert( dclass < EMIT_REGCLASSES )

	'' assume it will be trashed
	EMIT_REGSETUSED( dclass, reg )

	function = REG_ISFREE( emit.curnode->regFreeTB(dclass), reg )

end function

'':::::
private function hFindRegNotInVreg _
	( _
		byval vreg as IRVREG ptr, _
		byval noSIDI as integer = FALSE _
	) as integer static

    dim as integer r, reg, reg2, regs

	function = INVALID

	reg = INVALID

	select case vreg->typ
	case IR_VREGTYPE_REG
		reg = vreg->reg

	case IR_VREGTYPE_IDX, IR_VREGTYPE_PTR
		if( vreg->vidx <> NULL ) then
			if( vreg->vidx->typ = IR_VREGTYPE_REG ) then
				reg = vreg->vidx->reg
			end if
		end if
	end select

	'' longint..
	reg2 = INVALID
	if( vreg->vaux <> NULL ) then
		if( vreg->vaux->typ = IR_VREGTYPE_REG ) then
			reg2 = vreg->vaux->reg
		end if
	end if

	regs = emit.regTB(FB_DATACLASS_INTEGER)->getMaxRegs( emit.regTB(FB_DATACLASS_INTEGER) )

	''
	if( reg2 = INVALID ) then

		if( noSIDI = FALSE ) then

			for r = regs-1 to 0 step -1
				if( r <> reg ) then
					function = r
					if( hIsRegFree( FB_DATACLASS_INTEGER, r ) ) then
						exit function
					end if
				end if
			next

		'' SI/DI as byte..
		else

			for r = regs-1 to 0 step -1
				if( r <> reg ) then
					if( r <> EMIT_REG_ESI ) then
						if( r <> EMIT_REG_EDI ) then
							function = r
							if( hIsRegFree( FB_DATACLASS_INTEGER, r ) ) then
								exit function
							end if
						end if
					end if
				end if
			next

		end if

	'' longints..
	else

		if( noSIDI = FALSE ) then

			for r = regs-1 to 0 step -1
				if( (r <> reg) and (r <> reg2) ) then
					function = r
					if( hIsRegFree( FB_DATACLASS_INTEGER, r ) ) then
						exit function
					end if
				end if
			next

		'' SI/DI as byte..
		else

			for r = regs-1 to 0 step -1
				if( (r <> reg) and (r <> reg2) ) then
					if( r <> EMIT_REG_ESI ) then
						if( r <> EMIT_REG_EDI ) then
							function = r
							if( hIsRegFree( FB_DATACLASS_INTEGER, r ) ) then
								exit function
							end if
						end if
					end if
				end if
			next

		end if

	end if

end function

'':::::
private function hFindFreeReg _
	( _
		byval dclass as integer _
	) as integer static
    dim as integer r

	function = INVALID

	for r = emit.regTB(dclass)->getMaxRegs( emit.regTB(dclass) )-1 to 0 step -1
		function = r
		if( hIsRegFree( dclass, r ) ) then
			exit function
		end if
	next

end function

'':::::
private function hIsRegInVreg _
	( _
		byval vreg as IRVREG ptr, _
		byval reg as integer _
	) as integer static

	function = FALSE

	select case vreg->typ
	case IR_VREGTYPE_REG
		if( vreg->reg = reg ) then
			return TRUE
		end if

	case IR_VREGTYPE_IDX, IR_VREGTYPE_PTR
		if( vreg->vidx <> NULL ) then
			if( vreg->vidx->typ = IR_VREGTYPE_REG ) then
				if( vreg->vidx->reg = reg ) then
					return TRUE
				end if
			end if
		end if
	end select

	'' longints..
	if( vreg->vaux <> NULL ) then
		if( vreg->vaux->typ = IR_VREGTYPE_REG ) then
			if( vreg->vaux->reg = reg ) then
				return TRUE
			end if
		end if
	end if

end function

'':::::
private function hGetRegName _
	( _
		byval dtype as integer, _
		byval reg as integer _
	) as zstring ptr static

    dim as integer tb

	if( dtype >= FB_DATATYPE_POINTER ) then
		dtype = FB_DATATYPE_UINT
	end if

	if( reg = INVALID ) then
		function = NULL
	else
		tb = dtypeTB(dtype).rnametb

		function = @rnameTB(tb, reg)
	end if

end function

'':::::
private function hGetIdxName _
	( _
		byval vreg as IRVREG ptr _
	) as zstring ptr static

    static as zstring * FB_MAXINTNAMELEN+1+8+1+1+1+8+1 iname
    dim as FBSYMBOL ptr sym
    dim as IRVREG ptr vi
    dim as integer addone, mult
    dim as zstring ptr rname

	sym = vreg->sym
	vi  = vreg->vidx

	if( sym <> NULL ) then
		iname = *symbGetMangledName( sym )
		if( vi <> NULL ) then
			iname += "+"
		end if
	else
		iname = ""
	end if

	if( vi <> NULL ) then
		rname = hGetRegName( vi->dtype, vi->reg )

		iname += *rname

    	mult = vreg->mult
		if( mult > 1 ) then
			addone = FALSE
			select case mult
			case 3, 5, 9
				mult -= 1
				addone = TRUE
			end select

			iname += "*"
			iname += str( mult )

			if( addone ) then
				iname += "+"
				iname += *rname
			end if
		end if

	end if

	function = @iname

end function

'':::::
private sub hPrepOperand _
	( _
		byval vreg as IRVREG ptr, _
		byref operand as string, _
		byval dtype as FB_DATATYPE = INVALID, _
		byval ofs as integer = 0, _
		byval isaux as integer = FALSE, _
		byval addprefix as integer = TRUE _
	) static

    if( vreg = NULL ) then
    	operand = ""
    	exit sub
    end if

    if( dtype = INVALID ) then
    	dtype = vreg->dtype
    end if

	select case as const vreg->typ
	case IR_VREGTYPE_VAR, IR_VREGTYPE_IDX, IR_VREGTYPE_PTR

		if( addprefix ) then
			operand = dtypeTB(dtype).mname
			operand += " ["
		else
			operand = "["
		end if

		if( vreg->typ = IR_VREGTYPE_VAR ) then
			operand += *symbGetMangledName( vreg->sym )
		else
        	operand += *hGetIdxName( vreg )
		end if

		ofs += vreg->ofs
		if( isaux ) then
			ofs += FB_INTEGERSIZE
		end if

		if( ofs > 0 ) then
			operand += "+"
			operand += str( ofs )
		elseif( ofs < 0 ) then
			operand += str( ofs )
		end if

		operand += "]"

	case IR_VREGTYPE_OFS
		operand = "offset "
		operand += *symbGetMangledName( vreg->sym )
		if( vreg->ofs <> 0 ) then
			operand += " + "
			operand += str( vreg->ofs )
		end if

	case IR_VREGTYPE_REG
		if( isaux = FALSE ) then
			operand = *hGetRegName( dtype, vreg->reg )
		else
			operand = *hGetRegName( dtype, vreg->vaux->reg )
		end if

	case IR_VREGTYPE_IMM
		if( isaux = FALSE ) then
			operand = str( vreg->value )
		else
			operand = str( vreg->vaux->value )
		end if

	case else
    	operand = ""
	end select

end sub

'':::::
private sub hPrepOperand64 _
	( _
		byval vreg as IRVREG ptr, _
		byref operand1 as string, _
		byref operand2 as string _
	) static

	hPrepOperand( vreg, operand1, FB_DATATYPE_UINT   , 0, FALSE )
	hPrepOperand( vreg, operand2, FB_DATATYPE_INTEGER, 0, TRUE )

end sub

'':::::
private sub outEx _
	( _
		byval s as zstring ptr, _
		byval bytes as integer = 0 _
	) static

	if( bytes = 0 ) then
		bytes = len( *s )
	end if

	if( put( #env.outf.num, , *s, bytes ) = 0 ) then
	end if

end sub

'':::::
private sub outp _
	( _
		byval s as zstring ptr _
	) static

    dim as integer p, char
    dim as string ostr

	if( env.clopt.debug ) then
		p = instr( *s, " " )
		if( p > 0 ) then
			char = s[0][p-1]
			s[0][p-1] = CHAR_TAB		'' unsafe with constants..
		end if

		ostr = TABCHAR
		ostr += *s
		ostr += NEWLINE
		outEX( ostr, len( ostr ) )

		if( p > 0 ) then
			s[0][p-1] = char
		end if

	else

		ostr = *s
		ostr += NEWLINE
		outEX( ostr, len( ostr ) )

	end if

end sub

'':::::
private sub hBRANCH _
	( _
		byval mnemonic as zstring ptr, _
		byval label as zstring ptr _
	) static

    dim ostr as string

	ostr = *mnemonic
	ostr += " "
	ostr += *label
	outp( ostr )

end sub

'':::::
private sub hPUSH _
	( _
		byval rname as zstring ptr _
	) static

    dim ostr as string

	ostr = "push "
	ostr += *rname
	outp( ostr )

end sub

'':::::
private sub hPOP _
	( _
		byval rname as zstring ptr _
	) static

    dim ostr as string

    ostr = "pop "
    ostr += *rname
	outp( ostr )

end sub

'':::::
private sub hMOV _
	( _
		byval dname as zstring ptr, _
		byval sname as zstring ptr _
	) static

    dim ostr as string

	ostr = "mov "
	ostr += *dname
	ostr += ", "
	ostr += *sname
	outp( ostr )

end sub

'':::::
private sub hXCHG _
	( _
		byval dname as zstring ptr, _
		byval sname as zstring ptr _
	) static

    dim ostr as string

	ostr = "xchg "
	ostr += *dname
	ostr += ", "
	ostr += *sname
	outp( ostr )

end sub

'':::::
private sub hCOMMENT _
	( _
		byval s as zstring ptr _
	) static

    dim ostr as string

    ostr = TABCHAR + "#"
    ostr += *s
    ostr += NEWLINE
	outEX( ostr )

end sub

'':::::
private sub hPUBLIC _
	( _
		byval label as zstring ptr _
	) static

    dim ostr as string

	ostr = NEWLINE + ".globl "
	ostr += *label
	ostr += NEWLINE
	outEx( ostr )

end sub

'':::::
private sub hLABEL _
	( _
		byval label as zstring ptr _
	) static

    dim ostr as string

	ostr = *label
	ostr += ":" + NEWLINE
	outEx( ostr )

end sub

'':::::
private sub hALIGN _
	( _
		byval bytes as integer _
	) static

    dim ostr as string

    ostr = ".balign " + str( bytes ) + NEWLINE
	outEx( ostr )

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' implementation
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
private sub _emitLIT _
	( _
		byval s as zstring ptr )
    dim ostr as string

    ostr = *s + NEWLINE
	outEX( ostr )

end sub

'':::::
private sub _emitALIGN _
	( _
		byval vreg as IRVREG ptr _
	) static

    dim ostr as string

    ostr = ".balign " + str( vreg->value )
	outp( ostr )

end sub

'':::::
private sub _emitSTKALIGN _
	( _
		byval vreg as IRVREG ptr _
	) static

    dim ostr as string

    if( vreg->value > 0 ) then
    	ostr = "sub esp, " + str( vreg->value )
    else
    	ostr = "add esp, " + str( -vreg->value )
    end if

	outp( ostr )

end sub

'':::::
private sub _emitJMPTB _
	( _
		byval dtype as integer, _
		byval symbol as zstring ptr _
	) static

    dim ostr as string

	ostr = hGetTypeString( dtype ) + " " + *symbol
	outp( ostr )

end sub

'':::::
private sub _emitCALL _
	( _
		byval unused as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval bytestopop as integer _
	) static

    dim ostr as string

	ostr = "call "
	ostr += *symbGetMangledName( label )
	outp( ostr )

    if( bytestopop <> 0 ) then
    	ostr = "add esp, " + str( bytestopop )
    	outp( ostr )
    end if

end sub

'':::::
private sub _emitCALLPTR _
	( _
		byval svreg as IRVREG ptr, _
		byval unused as FBSYMBOL ptr, _
		byval bytestopop as integer _
	) static

    dim src as string
    dim ostr as string

	hPrepOperand( svreg, src )

	ostr = "call " + src
	outp( ostr )

    if( bytestopop <> 0 ) then
    	ostr = "add esp, " + str( bytestopop )
    	outp( ostr )
    end if

end sub

'':::::
private sub _emitBRANCH _
	( _
		byval unused as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval op as integer _
	) static

    dim ostr as string

	select case as const op
	case AST_OP_JLE
		ostr = "jle "
	case AST_OP_JGE
		ostr = "jge "
	case AST_OP_JLT
		ostr = "jl "
	case AST_OP_JGT
		ostr = "jg "
	case AST_OP_JEQ
		ostr = "je "
	case AST_OP_JNE
		ostr = "jne "
	end select

	ostr += *symbGetMangledName( label )
	outp( ostr )

end sub

'':::::
private sub _emitJUMP _
	( _
		byval unused1 as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval unused2 as integer _
	) static

    dim ostr as string

	ostr = "jmp "
	ostr += *symbGetMangledName( label )
	outp( ostr )

end sub

'':::::
private sub _emitJUMPPTR _
	( _
		byval svreg as IRVREG ptr, _
		byval unused1 as FBSYMBOL ptr, _
		byval unused2 as integer _
	) static

    dim src as string
    dim ostr as string

	hPrepOperand( svreg, src )

	ostr = "jmp " + src
	outp( ostr )

end sub

'':::::
private sub _emitRET _
	( _
		byval vreg as IRVREG ptr _
	) static

    dim ostr as string

    ostr = "ret " + str( vreg->value )
    outp( ostr )

end sub

'':::::
private sub _emitPUBLIC _
	( _
		byval label as FBSYMBOL ptr _
	) static

    dim ostr as string

	ostr = NEWLINE + ".globl "
	ostr += *symbGetMangledName( label )
	ostr += NEWLINE
	outEx( ostr )

end sub

'':::::
private sub _emitLABEL _
	( _
		byval label as FBSYMBOL ptr _
	) static

    dim ostr as string

	ostr = *symbGetMangledName( label )
	ostr += ":" + NEWLINE
	outEx( ostr )

end sub

'':::::
sub emitSECTION _
	( _
		byval section as integer _
	) static

    dim as string ostr

    if( section = emit.lastsection ) then
    	exit sub
    end if

	ostr = NEWLINE + ".section ."

	select case as const section
	case EMIT_SECTYPE_CONST
		ostr += "rodata"

	case EMIT_SECTYPE_DATA
		ostr += "data"

	case EMIT_SECTYPE_BSS
		ostr += "bss"

	case EMIT_SECTYPE_CODE
		ostr += "text"

	case EMIT_SECTYPE_DIRECTIVE
		ostr += "drectve"

	case EMIT_SECTYPE_CONSTRUCTOR
		ostr += "fb_ctors"
		if( env.clopt.target = FB_COMPTARGET_LINUX ) then
			ostr += ", " + QUOTE + "aw" + QUOTE + ", @progbits"
		end if

	case EMIT_SECTYPE_DESTRUCTOR
		ostr += "fb_dtors"
		if( env.clopt.target = FB_COMPTARGET_LINUX ) then
			ostr += ", " + QUOTE +  "aw" + QUOTE + ", @progbits"
		end if
	end select

	ostr += NEWLINE

	outEx( ostr )

	emit.lastsection = section

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' store
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
private sub hULONG2DBL _
	( _
		byval svreg as IRVREG ptr _
	) static

	dim as string label, src, ostr

	label = *hMakeTmpStr( )

	hPrepOperand( svreg, src, FB_DATATYPE_INTEGER, 4 )
	ostr = "cmp " +  src + ", 0"

	outp ostr
	ostr = "jns " + label
	outp ostr
	hPUSH( "16447" )
	hPUSH( "-2147483648" )
	hPUSH( "0" )
	outp "fldt [esp]"
	outp "add esp, 12"
	outp "faddp"
	hLABEL( label )

end sub

'':::::
private sub _emitSTORL2L _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst1, dst2, src1, src2, ostr

	hPrepOperand64( dvreg, dst1, dst2 )
	hPrepOperand64( svreg, src1, src2 )

	ostr = "mov " + dst1 + COMMA + src1
	outp ostr

	ostr = "mov " + dst2 + COMMA + src2
	outp ostr

end sub

'':::::
private sub _emitSTORI2L _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst1, dst2, src1, ext, ostr
    dim sdsize as integer

	sdsize = symbGetDataSize( svreg->dtype )

	hPrepOperand64( dvreg, dst1, dst2 )

	hPrepOperand( svreg, src1 )

	'' immediate?
	if( svreg->typ = IR_VREGTYPE_IMM ) then
		hMOV dst1, src1

		'' negative?
		if( symbIsSigned( svreg->dtype ) and (svreg->value and &h80000000) ) then
			hMOV dst2, "-1"
		else
			hMOV dst2, "0"
		end if

		exit sub
	end if

	''
	if( sdsize < FB_INTEGERSIZE ) then
		ext = *hGetRegName( FB_DATATYPE_INTEGER, svreg->reg )

		if( symbIsSigned( svreg->dtype ) ) then
			ostr = "movsx "
		else
			ostr = "movzx "
		end if
		ostr += ext + COMMA + src1
		outp ostr

	else
		ext = src1
	end if

	ostr = "mov " + dst1 + COMMA + ext
	outp ostr

	if( symbIsSigned( svreg->dtype ) ) then

		hPUSH ext

		ostr = "sar " + ext + ", 31"
		outp ostr

		ostr = "mov " + dst2 + COMMA + ext
		outp ostr

		hPOP ext

	else
		ostr = "mov " + dst2 + ", 0"
		outp ostr
	end if

end sub

'':::::
private sub _emitSTORF2L _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst
    dim as string ostr

	hPrepOperand( dvreg, dst )

	'' signed?
	if( symbIsSigned( dvreg->dtype ) ) then
		ostr = "fistp " + dst
		outp ostr

	end if

end sub

'':::::
private sub _emitSTORI2I _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst, src, aux, aux8, aux16
    dim as integer ddsize, reg, isfree
    dim as string ostr

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	ddsize = symbGetDataSize( dvreg->dtype )

	if( ddsize = 1 ) then
		if( svreg->typ = IR_VREGTYPE_IMM ) then
			ddsize = 4
		end if
	end if

	'' dst size = src size
	if( (svreg->typ = IR_VREGTYPE_IMM) or _
		(dvreg->dtype = svreg->dtype) or _
		(symbMaxDataType( dvreg->dtype, svreg->dtype ) = INVALID) ) then

		'' handle SI/DI as byte
		if( ddsize = 1 ) then
			if( svreg->typ = IR_VREGTYPE_REG ) then
				if( (svreg->reg = EMIT_REG_ESI) or (svreg->reg = EMIT_REG_EDI) ) then
					aux = *hGetRegName( dvreg->dtype, svreg->reg )
					goto storeSIDI
				end if
			end if
		end if

		ostr = "mov " + dst + COMMA + src
		outp ostr

	'' sizes are different..
	else

		aux = *hGetRegName( dvreg->dtype, svreg->reg )

		'' dst size > src size
		if( dvreg->dtype > svreg->dtype ) then
			if( symbIsSigned( svreg->dtype ) ) then
				ostr = "movsx "
			else
				ostr = "movzx "
			end if
			ostr += aux + COMMA + src
			outp ostr

			ostr = "mov " + dst + COMMA + aux
			outp ostr

		'' dst size < src size
		else
			'' handle DI/SI as byte
			if( (ddsize = 1) and _
				((svreg->reg = EMIT_REG_ESI) or (svreg->reg = EMIT_REG_EDI)) ) then

storeSIDI:		reg = hFindRegNotInVreg( dvreg, TRUE )

				aux8  = *hGetRegName( FB_DATATYPE_BYTE, reg )
				aux16 = *hGetRegName( FB_DATATYPE_SHORT, reg )

				isfree = hIsRegFree(FB_DATACLASS_INTEGER, reg )

				if( isfree = FALSE ) then
					hPUSH aux16
				end if

				hMOV aux16, aux

            	'' handle DI/SI as destine
            	if( (dvreg->typ = IR_VREGTYPE_REG) and _
            		((dvreg->reg = EMIT_REG_ESI) or (dvreg->reg = EMIT_REG_EDI)) ) then
					if( symbIsSigned( dvreg->dtype ) ) then
						ostr = "movsx "
					else
						ostr = "movzx "
					end if
					ostr += dst + COMMA + aux8
					outp ostr
				else
					hMOV dst, aux8
				end if

				if( isfree = FALSE ) then
					hPOP aux16
				end if

			else
				ostr = "mov " + dst + COMMA + aux
				outp ostr
			end if
		end if
	end if

end sub

'':::::
private sub _emitSTORL2I _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	'' been too complex due the SI/DI crap, leave it to I2I
	_emitSTORI2I( dvreg, svreg )

end sub

'':::::
private sub _emitSTORF2I _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst, src, aux, aux8, aux16
    dim as integer ddsize, reg, isfree
    dim as string ostr

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	ddsize = symbGetDataSize( dvreg->dtype )

	'' byte destine? damn..
	if( ddsize = 1 ) then

		outp "sub esp, 4"
		outp "fistp dword ptr [esp]"

        '' destine is a reg?
        if( dvreg->typ = IR_VREGTYPE_REG ) then

           	'' handle DI/SI as destine
           	if( (dvreg->reg = EMIT_REG_ESI) or (dvreg->reg = EMIT_REG_EDI) ) then

           		if( symbIsSigned( dvreg->dtype ) ) then
	           		ostr = "movsx "
           		else
           			ostr = "movzx "
           		end if
           		ostr += dst + ", byte ptr [esp]"
           		outp ostr

           	else
           		hMOV dst, "byte ptr [esp]"
           	end if

           	outp "add esp, 4"

		'' destine is a var/idx/ptr
		else

			reg = hFindRegNotInVreg( dvreg, TRUE )

			aux8 = *hGetRegName( FB_DATATYPE_BYTE, reg )
			aux  = *hGetRegName( FB_DATATYPE_INTEGER, reg )

			isfree = hIsRegFree( FB_DATACLASS_INTEGER, reg )

			if( isfree = FALSE ) then
				hXCHG aux, "dword ptr [esp]"
			else
				hMOV aux8, "byte ptr [esp]"
			end if

			hMOV dst, aux8

			if( isfree = FALSE ) then
				hPOP aux
			else
				outp "add esp, 4"
			end if

		end if

	else
		'' signed?
		if( symbIsSigned( dvreg->dtype ) ) then
			ostr = "fistp " + dst
			outp ostr

		'' unsigned.. try a bigger type
		else
			'' uint?
			if( ddsize = FB_INTEGERSIZE ) then
				outp "sub esp, 8"
				outp "fistp qword ptr [esp]"
				hPOP dst
				outp  "add esp, 4"

			'' ushort..
			else
				outp "sub esp, 4"
				outp "fistp dword ptr [esp]"
				hPOP dst
				outp  "add esp, 2"
			end if
		end if

	end if

end sub

'':::::
private sub _emitSTORL2F _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst, src, aux
    dim as string ostr

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	if( (svreg->typ = IR_VREGTYPE_REG) or (svreg->typ = IR_VREGTYPE_IMM) ) then

		'' signed?
		if( symbIsSigned( svreg->dtype ) ) then

			hPrepOperand64( svreg, src, aux )

			hPUSH( aux )
			hPUSH( src )

			ostr = "fild " + dtypeTB(svreg->dtype).mname + " [esp]"
			outp ostr

			outp "add esp, 8"

		'' unsigned..
		else
			hPrepOperand64( svreg, src, aux )
			hPUSH aux
			hPUSH src
			outp "fild qword ptr [esp]"
			outp "add esp, 8"
			hULONG2DBL( svreg )

		end if

	'' not a reg or imm
	else
		'' signed?
		if( symbIsSigned( svreg->dtype ) ) then
			ostr = "fild " + src
			outp ostr

		'' unsigned, try a bigger type..
		else
			ostr = "fild " + src
			outp ostr
			hULONG2DBL( svreg )

		end if
	end if

	ostr = "fstp " + dst
	outp ostr

end sub

'':::::
private sub _emitSTORI2F _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst, src, aux
    dim as integer ddsize, sdsize, reg, isfree
    dim as string ostr

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	ddsize = symbGetDataSize( dvreg->dtype )
	sdsize = symbGetDataSize( svreg->dtype )

	'' byte source? damn..
	if( sdsize = 1 ) then

		reg = hFindRegNotInVreg( svreg )

		aux = *hGetRegName( FB_DATATYPE_INTEGER, reg )

		isfree = hIsRegFree( FB_DATACLASS_INTEGER, reg )

		if( isfree = FALSE ) then
			hPUSH aux
		end if

		if( symbIsSigned( svreg->dtype ) ) then
			ostr = "movsx "
		else
			ostr = "movzx "
		end if
		ostr += aux + COMMA + src
		outp ostr

		hPUSH aux
		outp "fild dword ptr [esp]"
		outp "add esp, 4"

		if( isfree = FALSE ) then
			hPOP aux
		end if

		ostr = "fstp " + dst
		outp ostr

		exit sub
	end if

	''
	if( (svreg->typ = IR_VREGTYPE_REG) or (svreg->typ = IR_VREGTYPE_IMM) ) then

		'' signed?
		if( symbIsSigned( svreg->dtype ) ) then

			'' not an integer? make it
			if( (svreg->typ = IR_VREGTYPE_REG) and (sdsize < FB_INTEGERSIZE) ) then
				src = *hGetRegName( FB_DATATYPE_INTEGER, svreg->reg )
			end if

			hPUSH src

			ostr = "fild " + dtypeTB(svreg->dtype).mname + " [esp]"
			outp ostr

			outp "add esp, 4"

		'' unsigned..
		else

			'' uint..
			if( sdsize = FB_INTEGERSIZE ) then
				hPUSH "0"
				hPUSH src
				outp "fild qword ptr [esp]"
				outp "add esp, 8"

			'' ushort..
			else
				if( svreg->typ <> IR_VREGTYPE_IMM ) then
					hPUSH "0"
				end if

				hPUSH src
				outp "fild dword ptr [esp]"

				if( svreg->typ <> IR_VREGTYPE_IMM ) then
					outp "add esp, 6"
				else
					outp "add esp, 4"
				end if
			end if

		end if

	'' not a reg or imm
	else

		'' signed?
		if( symbIsSigned( svreg->dtype ) ) then
			ostr = "fild " + src
			outp ostr

		'' unsigned, try a bigger type..
		else
			'' uint..
			if( sdsize = FB_INTEGERSIZE ) then
				hPUSH "0"
				hPUSH src
				outp "fild qword ptr [esp]"
				outp "add esp, 8"

			'' ushort..
			else
				hPUSH "0"
				hPUSH src
				outp "fild dword ptr [esp]"
				outp "add esp, 6"
			end if

		end if
	end if

	ostr = "fstp " + dst
	outp ostr

end sub

'':::::
private sub _emitSTORF2F _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst, src
    dim as integer ddsize, sdsize
    dim as string ostr

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	ddsize = symbGetDataSize( dvreg->dtype )
	sdsize = symbGetDataSize( svreg->dtype )

	'' on fpu stack?
	if( svreg->typ = IR_VREGTYPE_REG ) then
		ostr = "fstp " + dst
		outp ostr

	else
		'' same size? just copy..
		if( sdsize = ddsize ) then

			hPrepOperand( svreg, src, FB_DATATYPE_INTEGER, 0 )
			ostr = "push " + src
			outp ostr

			if( sdsize > 4 ) then
				hPrepOperand( svreg, src, FB_DATATYPE_INTEGER, 4 )
				ostr = "push " + src
				outp ostr

				hPrepOperand( dvreg, dst, FB_DATATYPE_INTEGER, 4 )
				ostr = "pop " + dst
				outp ostr
			end if

			hPrepOperand( dvreg, dst, FB_DATATYPE_INTEGER, 0 )
			ostr = "pop " + dst
			outp ostr

		'' diff sizes, convert..
		else
			ostr = "fld " + src
			outp ostr

			ostr = "fstp " + dst
			outp ostr
		end if
	end if

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' load
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
private sub _emitLOADL2L _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim dst1 as string, dst2 as string, src1 as string, src2 as string
    dim ostr as string

	hPrepOperand64( dvreg, dst1, dst2 )
	hPrepOperand64( svreg, src1, src2 )

	ostr = "mov " + dst1 + COMMA + src1
	outp ostr

	ostr = "mov " + dst2 + COMMA + src2
	outp ostr

end sub

'':::::
private sub _emitLOADI2L _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim dst1 as string, dst2 as string, src1 as string
    dim sdsize as integer
    dim ostr as string

	sdsize = symbGetDataSize( svreg->dtype )

	hPrepOperand64( dvreg, dst1, dst2 )

	hPrepOperand( svreg, src1 )

	'' immediate?
	if( svreg->typ = IR_VREGTYPE_IMM ) then

        hMOV dst1, src1

		'' negative?
		if( symbIsSigned( svreg->dtype ) and (svreg->value and &h80000000) ) then
			hMOV dst2, "-1"
		else
			hMOV dst2, "0"
		end if

		exit sub
	end if

	''
	if( symbIsSigned( svreg->dtype ) ) then

		if( sdsize < FB_INTEGERSIZE ) then
			ostr = "movsx " + dst1 + COMMA + src1
			outp ostr
		else
			hMOV dst1, src1
		end if

		hMOV dst2, dst1

		ostr = "sar " + dst2 + ", 31"
		outp ostr

	else

		if( sdsize < FB_INTEGERSIZE ) then
			ostr = "movzx " + dst1 + COMMA + src1
			outp ostr
		else
			hMOV dst1, src1
		end if

		hMOV dst2, "0"

	end if

end sub

'':::::
private sub _emitLOADF2L _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst, src, aux
    dim as string ostr

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	if( svreg->typ <> IR_VREGTYPE_REG ) then
		ostr = "fld " + src
		outp ostr
	end if

	'' signed?
	if( symbIsSigned( dvreg->dtype ) ) then

		outp "sub esp, 8"

		ostr = "fistp " + dtypeTB(dvreg->dtype).mname + " [esp]"
		outp ostr

		hPrepOperand64( dvreg, dst, aux )

		hPOP( dst )
		hPOP( aux )


	'' unsigned.. try a bigger type
	else

		'' handled by AST already..

	end if

end sub

'':::::
private sub _emitLOADI2I _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst, src, aux, aux8, aux16
    dim as integer ddsize, reg, isfree
    dim as string ostr

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	ddsize = symbGetDataSize( dvreg->dtype )

	if( ddsize = 1 ) then
		if( svreg->typ = IR_VREGTYPE_IMM ) then
			ddsize = 4
		end if
	end if

	'' dst size = src size
	if( (dvreg->dtype = svreg->dtype) or _
		(symbMaxDataType( dvreg->dtype, svreg->dtype ) = INVALID) ) then

		'' handle SI/DI as byte destine and source
		if( ddsize = 1 ) then
			if( (dvreg->reg = EMIT_REG_ESI) or (dvreg->reg = EMIT_REG_EDI) ) then
				goto loadSIDI
			elseif( svreg->typ = IR_VREGTYPE_REG ) then
				if( (svreg->reg = EMIT_REG_ESI) or (svreg->reg = EMIT_REG_EDI) ) then
					goto loadSIDI
				end if
			end if
		end if

		ostr = "mov " + dst + COMMA + src
		outp ostr

	else
		'' dst size > src size
		if( dvreg->dtype > svreg->dtype ) then
			if( symbIsSigned( svreg->dtype ) ) then
				ostr = "movsx "
			else
				ostr = "movzx "
			end if
			ostr += dst + COMMA + src
			outp ostr

		'' dst dize < src size
		else
			'' is src a reg too?
			if( svreg->typ = IR_VREGTYPE_REG ) then
				if( svreg->reg <> dvreg->reg ) then
					aux = *hGetRegName( dvreg->dtype, svreg->reg )
					ostr = "mov " + dst + COMMA + aux
					outp ostr
				end if

			'' src is not a reg
			else
				'' handle DI/SI as byte
				if( (ddsize = 1) and _
					((dvreg->reg = EMIT_REG_ESI) or (dvreg->reg = EMIT_REG_EDI)) ) then

loadSIDI:			reg = hFindRegNotInVreg( dvreg, TRUE )

					aux8  = *hGetRegName( FB_DATATYPE_BYTE, reg )
					aux16 = *hGetRegName( FB_DATATYPE_SHORT, reg )

					isfree = hIsRegFree( FB_DATACLASS_INTEGER, reg )

					if( isfree = FALSE ) then
						hPUSH aux16
					end if

					hPrepOperand( svreg, src, dvreg->dtype )

					'' handle SI/DI as source
					if( (svreg->typ = IR_VREGTYPE_REG) and _
           				((svreg->reg = EMIT_REG_ESI) or (svreg->reg = EMIT_REG_EDI)) ) then
						hMOV aux16, src
					else
						hMOV aux8, src
					end if

					if( symbIsSigned( svreg->dtype ) ) then
						ostr = "movsx "
					else
						ostr = "movzx "
					end if
					ostr += dst + COMMA + aux8
					outp ostr

					if( isfree = FALSE ) then
						hPOP aux16
					end if

				'' SI/DI not used as byte
				else
					hPrepOperand( svreg, src, dvreg->dtype )
					ostr = "mov " + dst + COMMA + src
					outp ostr
				end if
			end if
		end if
	end if

end sub

'':::::
private sub _emitLOADL2I _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	'' been too complex due the SI/DI crap, leave it to I2I
	_emitLOADI2I( dvreg, svreg )

end sub

'':::::
private sub _emitLOADF2I _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst, src, aux, aux8
    dim as integer ddsize, reg, isfree
    dim as string ostr

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	ddsize = symbGetDataSize( dvreg->dtype )

	if( svreg->typ <> IR_VREGTYPE_REG ) then
		ostr = "fld " + src
		outp ostr
	end if

	'' byte destine? damn..
	if( ddsize = 1 ) then

		outp "sub esp, 4"
        outp "fistp dword ptr [esp]"

    	'' destine is a reg
    	if( dvreg->typ = IR_VREGTYPE_REG ) then
    		'' handle DI/SI as destine
        	if( (dvreg->reg = EMIT_REG_ESI) or (dvreg->reg = EMIT_REG_EDI) ) then
				if( symbIsSigned( dvreg->dtype ) ) then
					ostr = "movsx "
				else
					ostr = "movzx "
				end if
				ostr += dst + ", byte ptr [esp]"
				outp ostr

			else
				hMOV dst, "byte ptr [esp]"
			end if

			outp "add esp, 4"

		'' destine is a var/idx/ptr
        else

			reg = hFindRegNotInVreg( dvreg, TRUE )

			aux8 = *hGetRegName( FB_DATATYPE_BYTE, reg )
			aux  = *hGetRegName( FB_DATATYPE_INTEGER, reg )

			isfree = hIsRegFree( FB_DATACLASS_INTEGER, reg )

			if( isfree = FALSE ) then
				hXCHG aux, "dword ptr [esp]"
			else
				hMOV aux8, "byte ptr [esp]"
			end if

			hMOV dst, aux8

			if( isfree = FALSE ) then
				hPOP aux
			else
				outp "add esp, 4"
			end if

        end if

	else

		'' signed?
		if( symbIsSigned( dvreg->dtype ) ) then

			outp "sub esp, 4"

			ostr = "fistp " + dtypeTB(dvreg->dtype).mname + " [esp]"
			outp ostr

			'' not an integer? make it
			if( ddsize < FB_INTEGERSIZE ) then
				dst = *hGetRegName( FB_DATATYPE_INTEGER, dvreg->reg )
			end if

			hPOP dst

		'' unsigned.. try a bigger type
		else

			'' uint?
			if( ddsize = FB_INTEGERSIZE ) then
				outp "sub esp, 8"
				outp "fistp qword ptr [esp]"
				hPOP dst
				outp  "add esp, 4"

			'' ushort..
			else
				outp "sub esp, 4"
				outp "fistp dword ptr [esp]"
				hPOP dst
				outp  "add esp, 2"
			end if

		end if

	end if

end sub

'':::::
private sub _emitLOADL2F _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst, src, aux
    dim as string ostr

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	if( (svreg->typ = IR_VREGTYPE_REG) or (svreg->typ = IR_VREGTYPE_IMM) ) then

		'' signed?
		if( symbIsSigned( svreg->dtype ) ) then

			hPrepOperand64( svreg, src, aux )

			hPUSH( aux )
			hPUSH( src )

			ostr = "fild " + dtypeTB(svreg->dtype).mname + " [esp]"
			outp ostr

			outp "add esp, 8"

		'' unsigned, try a bigger type..
		else

			hPrepOperand64( svreg, src, aux )
			hPUSH aux
			hPUSH src
			outp "fild qword ptr [esp]"
			outp "add esp, 8"
			hULONG2DBL( svreg )

		end if

	'' not a reg or imm
	else

		'' signed?
		if( symbIsSigned( svreg->dtype ) ) then
			ostr = "fild " + src
			outp ostr

		'' unsigned, try a bigger type..
		else
			ostr = "fild " + src
			outp ostr
			hULONG2DBL( svreg )

		end if

	end if

end sub

'':::::
private sub _emitLOADI2F _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst, src, aux
    dim as integer sdsize, isfree, reg
    dim as string ostr

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

    sdsize = symbGetDataSize( svreg->dtype )

	'' byte source? damn..
	if( sdsize = 1 ) then

		reg = hFindRegNotInVreg( svreg )

		aux = *hGetRegName( FB_DATATYPE_INTEGER, reg )

		isfree = hIsRegFree( FB_DATACLASS_INTEGER, reg )

		if( isfree = FALSE ) then
			hPUSH aux
		end if

		if( symbIsSigned( svreg->dtype ) ) then
			ostr = "movsx " + aux + COMMA + src
			outp ostr
		else
			ostr = "movzx " + aux + COMMA + src
			outp ostr
		end if

		hPUSH aux
		outp "fild dword ptr [esp]"
		outp "add esp, 4"

		if( isfree = FALSE ) then
			hPOP aux
		end if

		exit sub
	end if

	''
	if( (svreg->typ = IR_VREGTYPE_REG) or (svreg->typ = IR_VREGTYPE_IMM) ) then

		'' signed?
		if( symbIsSigned( svreg->dtype ) ) then

			'' not an integer? make it
			if( (svreg->typ = IR_VREGTYPE_REG) and (sdsize < FB_INTEGERSIZE) ) then
				src = *hGetRegName( FB_DATATYPE_INTEGER, svreg->reg )
			end if

			hPUSH src

			ostr = "fild " + dtypeTB(svreg->dtype).mname + " [esp]"
			outp ostr

			outp "add esp, 4"

		'' unsigned, try a bigger type..
		else

			'' uint?
			if( sdsize = FB_INTEGERSIZE ) then
				hPUSH "0"
				hPUSH src
				outp "fild qword ptr [esp]"
				outp "add esp, 8"

			'' ushort..
			else
				if( svreg->typ <> IR_VREGTYPE_IMM ) then
					hPUSH "0"
				end if

				hPUSH src
				outp "fild dword ptr [esp]"

				if( svreg->typ <> IR_VREGTYPE_IMM ) then
					outp "add esp, 6"
				else
					outp "add esp, 4"
				end if
			end if

		end if

	'' not a reg or imm
	else

		'' signed?
		if( symbIsSigned( svreg->dtype ) ) then
			ostr = "fild " + src
			outp ostr

		'' unsigned, try a bigger type..
		else
			'' uint..
			if( sdsize = FB_INTEGERSIZE ) then
				hPUSH "0"
				hPUSH src
				outp "fild qword ptr [esp]"
				outp "add esp, 8"

			'' ushort..
			else
				hPUSH "0"
				hPUSH src
				outp "fild dword ptr [esp]"
				outp "add esp, 6"
			end if
		end if

	end if

end sub

'':::::
private sub _emitLOADF2F _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string src
    dim as string ostr

	hPrepOperand( svreg, src )

	ostr = "fld " + src
	outp ostr

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' binary ops
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
private sub _emitMOVL _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst1, dst2, src1, src2, ostr

	hPrepOperand64( dvreg, dst1, dst2 )
	hPrepOperand64( svreg, src1, src2 )

	ostr = "mov " + dst1 + COMMA + src1
	outp ostr

	ostr = "mov " + dst2 + COMMA + src2
	outp ostr

end sub

'':::::
private sub _emitMOVI _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst, src, ostr

	'' byte? handle SI, DI used as bytes..
	if( symbGetDataSize( dvreg->dtype ) = 1 ) then
		'' MOV is only used when both operands are registers
		dst = *hGetRegName( FB_DATATYPE_INTEGER, dvreg->reg )
		src = *hGetRegName( FB_DATATYPE_INTEGER, svreg->reg )
	else
		hPrepOperand( dvreg, dst )
		hPrepOperand( svreg, src )
	end if

	ostr = "mov " + dst + COMMA + src
	outp ostr

end sub

'':::::
private sub _emitMOVF _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	'' do nothing, both are regs

end sub

'':::::
private sub _emitADDL _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim dst1 as string, dst2 as string, src1 as string, src2 as string
    dim ostr as string

	hPrepOperand64( dvreg, dst1, dst2 )
	hPrepOperand64( svreg, src1, src2 )

	ostr = "add " + dst1 + COMMA + src1
	outp ostr

	ostr = "adc " + dst2 + COMMA + src2
	outp ostr

end sub

'':::::
private sub _emitADDI _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim dst as string, src as string
    dim doinc as integer, dodec as integer
    dim ostr as string

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	doinc = FALSE
	dodec = FALSE
	if( svreg->typ = IR_VREGTYPE_IMM ) then
		select case svreg->value
		case 1
			doinc = TRUE
		case -1
			dodec = TRUE
		end select
	end if

	if( doinc ) then
		ostr = "inc " + dst
		outp ostr
	elseif( dodec ) then
		ostr = "dec " + dst
		outp ostr
	else
		ostr = "add " + dst + COMMA + src
		outp ostr
	end if

end sub

'':::::
private sub _emitADDF _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim src as string
    dim ostr as string

	hPrepOperand( svreg, src )

	if( svreg->typ = IR_VREGTYPE_REG ) then
		ostr = "faddp"
		outp ostr
	else
		if( symbGetDataClass( svreg->dtype ) = FB_DATACLASS_FPOINT ) then
			ostr = "fadd " + src
			outp ostr
		else
			ostr = "fiadd " + src
			outp ostr
		end if
	end if

end sub

'':::::
private sub _emitSUBL _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim dst1 as string, dst2 as string, src1 as string, src2 as string
    dim ostr as string

	hPrepOperand64( dvreg, dst1, dst2 )
	hPrepOperand64( svreg, src1, src2 )

	ostr = "sub " + dst1 + COMMA + src1
	outp ostr

	ostr = "sbb " + dst2 + COMMA + src2
	outp ostr

end sub

'':::::
private sub _emitSUBI _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim dst as string, src as string
    dim doinc as integer, dodec as integer
    dim ostr as string

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	doinc = FALSE
	dodec = FALSE
	if( svreg->typ = IR_VREGTYPE_IMM ) then
		select case svreg->value
		case 1
			dodec = TRUE
		case -1
			doinc = TRUE
		end select
	end if

	if( dodec ) then
		ostr = "dec " + dst
		outp ostr
	elseif( doinc ) then
		ostr = "inc " + dst
		outp ostr
	else
		ostr = "sub " + dst + COMMA + src
		outp ostr
	end if

end sub

'':::::
private sub _emitSUBF _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim src as string
    dim doinc as integer, dodec as integer
    dim ostr as string

	hPrepOperand( svreg, src )

	if( svreg->typ = IR_VREGTYPE_REG ) then
		outp "fsubrp"
	else
		if( symbGetDataClass( svreg->dtype ) = FB_DATACLASS_FPOINT ) then
			ostr = "fsub " + src
			outp ostr
		else
			ostr = "fisub " + src
			outp ostr
		end if
	end if

end sub

'':::::
private sub _emitMULI _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim eaxfree as integer, edxfree as integer
    dim edxtrashed as integer
    dim eaxinsource as integer, eaxindest as integer, edxindest as integer
    dim eax as string, edx as string
    dim ostr as string
    dim dst as string, src as string

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	eaxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_EAX )
	edxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_EDX )

	eaxinsource = hIsRegInVreg( svreg, EMIT_REG_EAX )
	eaxindest = hIsRegInVreg( dvreg, EMIT_REG_EAX )
	edxindest = hIsRegInVreg( dvreg, EMIT_REG_EDX )

    if( dtypeTB(dvreg->dtype).size = 4 ) then
    	eax = "eax"
    	edx = "edx"
    else
    	eax = "ax"
    	edx = "dx"
    end if

	if( (eaxinsource) or (svreg->typ = IR_VREGTYPE_IMM) ) then
		edxtrashed = TRUE
		if( edxindest ) then
			hPUSH( "edx" )
			if( dvreg->typ <> IR_VREGTYPE_REG ) then
				hPrepOperand( dvreg, ostr, FB_DATATYPE_INTEGER )
				hPUSH( ostr )
			end if
		elseif( edxfree = FALSE ) then
			hPUSH( "edx" )
		end if

		hMOV( edx, src )
		src = edx
	else
		edxtrashed = FALSE
	end if

	if( (eaxindest = FALSE) or (dvreg->typ <> IR_VREGTYPE_REG) ) then
		if( (edxindest) and (edxtrashed) ) then
			if( eaxfree = FALSE ) then
				outp "xchg eax, [esp]"
			else
				hPOP "eax"
			end if
		else
			if( eaxfree = FALSE ) then
				hPUSH "eax"
			end if
			hMOV eax, dst
		end if
	end if

	ostr = "mul " + src
	outp ostr

	if( eaxindest = FALSE ) then
		if( edxindest and dvreg->typ <> IR_VREGTYPE_REG ) then
			hPOP "edx"					'' edx= tos (eax)
			outp "xchg edx, [esp]"			'' tos= edx; edx= dst
		end if

		hMOV dst, eax

		if( eaxfree = FALSE ) then
			hPOP "eax"
		end if
	else
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			hMOV "edx", "eax"			'' edx= eax
			hPOP "eax"					'' restore eax
			hMOV dst, edx				'' [eax+...] = edx
		end if
	end if

	if( edxtrashed ) then
		if( (edxfree = FALSE) and (edxindest = FALSE) ) then
			hPOP "edx"
		end if
	end if

end sub

'':::::
private sub _emitMULL _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim dst1 as string, dst2 as string, src1 as string, src2 as string
    dim iseaxfree as integer, isedxfree as integer
    dim eaxindest as integer, edxindest as integer
    dim ofs as integer

	hPrepOperand64( dvreg, dst1, dst2 )
	hPrepOperand64( svreg, src1, src2 )

	iseaxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_EAX )
	isedxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_EDX )

	eaxindest = hIsRegInVreg( dvreg, EMIT_REG_EAX )
	edxindest = hIsRegInVreg( dvreg, EMIT_REG_EDX )

	hPUSH( src2 )
	hPUSH( src1 )
	hPUSH( dst2 )
	hPUSH( dst1 )

	ofs = 0

	if( edxindest ) then
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			ofs += 4
			hPUSH( "edx" )
		end if
	else
		if( isedxfree = FALSE ) then
			ofs += 4
			hPUSH( "edx" )
		end if
	end if

	if( eaxindest ) then
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			ofs += 4
			hPUSH "eax"
		end if
	else
		if( iseaxfree = FALSE ) then
			ofs += 4
			hPUSH "eax"
		end if
	end if

	'' res = low(dst) * low(src)
	outp "mov eax, [esp+" + str( 0+ofs ) + "]"
	outp "mul dword ptr [esp+" + str( 8+ofs ) + "]"

	'' hres= low(dst) * high(src) + high(res)
	outp "xchg eax, [esp+" + str ( 0+ofs ) + "]"

	outp "imul eax, [esp+" + str ( 12+ofs ) + "]"
	outp "add eax, edx"

	'' hres += high(dst) * low(src)
	outp "mov edx, [esp+" + str( 4+ofs ) + "]"
	outp "imul edx, [esp+" + str( 8+ofs ) + "]"
	outp "add edx, eax"
	outp "mov [esp+" + str( 4+ofs ) + "], edx"

	if( eaxindest ) then
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			hPOP "eax"
		end if
	else
		if( iseaxfree = FALSE ) then
			hPOP "eax"
		end if
	end if

	if( edxindest ) then
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			hPOP "edx"
		end if
	else
		if( isedxfree = FALSE ) then
			hPOP "edx"
		end if
	end if

	'' low(dst) = low(res)
	hPOP dst1
	'' high(dst) = hres
	hPOP dst2

	outp "add esp, 8"

	'' code:
	'' mov	eax, low(dst)
	'' mul	low(src)
	'' mov	ebx, low(dst)
	'' imul	ebx, high(src)
	'' add	ebx, edx
	'' mov	edx, high(dst)
	'' imul	edx, low(src)
	'' add	edx, ebx
	'' mov	low(dst), eax
	'' mov	high(dst), edx

end sub

'':::::
private sub _emitSMULI _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim reg as integer, isfree as integer, rname as string
    dim ostr as string
    dim dst as string, src as string

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	if( dvreg->typ <> IR_VREGTYPE_REG ) then

		reg = hFindRegNotInVreg( svreg )
		rname = *hGetRegName( svreg->dtype, reg )

		isfree = hIsRegFree( FB_DATACLASS_INTEGER, reg )

		if( isfree = FALSE ) then
			hPUSH rname
		end if

		hMOV rname, dst
		ostr = "imul " + rname + COMMA + src
		outp ostr
		hMOV dst, rname

		if( isfree = FALSE ) then
			hPOP rname
		end if

	else
		ostr = "imul " + dst + COMMA + src
		outp ostr
	end if

end sub

'':::::
private sub _emitMULF _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim src as string
    dim ostr as string

	hPrepOperand( svreg, src )

	if( svreg->typ = IR_VREGTYPE_REG ) then
		outp "fmulp"
	else
		if( symbGetDataClass( svreg->dtype ) = FB_DATACLASS_FPOINT ) then
			ostr = "fmul " + src
			outp ostr
		else
			ostr = "fimul " + src
			outp ostr
		end if
	end if

end sub


'':::::
private sub _emitDIVF _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim src as string
    dim ostr as string

	hPrepOperand( svreg, src )

	if( svreg->typ = IR_VREGTYPE_REG ) then
		outp "fdivrp"
	else
		if( symbGetDataClass( svreg->dtype ) = FB_DATACLASS_FPOINT ) then
			ostr = "fdiv " + src
			outp ostr
		else
			ostr = "fidiv " + src
			outp ostr
		end if
	end if

end sub

'':::::
private sub _emitDIVI _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst, src
    dim as integer ecxtrashed
    dim as integer eaxfree, ecxfree, edxfree
    dim as integer eaxindest, ecxindest, edxindest
    dim as integer eaxinsource, edxinsource
    dim as string eax, ecx, edx
    dim as string ostr

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

    if( dtypeTB(dvreg->dtype).size = 4 ) then
    	eax = "eax"
    	ecx = "ecx"
    	edx = "edx"
    else
    	eax = "ax"
    	ecx = "cx"
    	edx = "dx"
    end if

	ecxtrashed = FALSE

	eaxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_EAX )
	ecxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_ECX )
	edxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_EDX )

	eaxinsource = hIsRegInVreg( svreg, EMIT_REG_EAX )
	edxinsource = hIsRegInVreg( svreg, EMIT_REG_EDX )
	eaxindest = hIsRegInVreg( dvreg, EMIT_REG_EAX )
	edxindest = hIsRegInVreg( dvreg, EMIT_REG_EDX )
	ecxindest = hIsRegInVreg( dvreg, EMIT_REG_ECX )

	if( (eaxinsource) or (edxinsource) or (svreg->typ = IR_VREGTYPE_IMM) ) then
		ecxtrashed = TRUE
		if( ecxindest ) then
			hPUSH( "ecx" )
			if( dvreg->typ <> IR_VREGTYPE_REG ) then
				hPrepOperand( dvreg, ostr, FB_DATATYPE_INTEGER )
				hPUSH( ostr )
			end if
		elseif( ecxfree = FALSE ) then
			hPUSH( "ecx" )
		end if
		hMOV( ecx, src )
		src = ecx
	end if

	if( eaxindest = FALSE ) then
		if( (ecxindest) and (ecxtrashed) ) then
			if( eaxfree = FALSE ) then
				outp "xchg eax, [esp]"
			else
				hPOP "eax"
			end if
		else
			if( eaxfree = FALSE ) then
				hPUSH "eax"
			end if
			hMOV eax, dst
		end if

	else
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			hPUSH "eax"
			hMOV eax, dst
		end if
	end if

	if( edxindest ) then
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			hPUSH "edx"
		end if
	elseif( edxfree = FALSE ) then
		hPUSH "edx"
	end if

	if( symbIsSigned( dvreg->dtype ) ) then
		if( dtypeTB(dvreg->dtype).size = 4 ) then
			outp "cdq"
		else
			outp "cwd"
		end if

		ostr = "idiv " + src
		outp ostr

	else
		ostr = "xor " + edx + ", " + edx
		outp ostr

		ostr = "div " + src
		outp ostr
	end if

	if( edxindest ) then
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			hPOP "edx"
		end if
	elseif( edxfree = FALSE ) then
		hPOP "edx"
	end if

	if( eaxindest = FALSE ) then
		if( ecxindest and ecxtrashed ) then
			if( dvreg->typ <> IR_VREGTYPE_REG ) then
				hPOP "ecx"					'' ecx= tos (eax)
				outp "xchg ecx, [esp]"			'' tos= ecx; ecx= dst
			end if
		end if

		hMOV dst, eax

		if( eaxfree = FALSE ) then
			hPOP "eax"
		end if

	else
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			if( (ecxfree = FALSE) and (ecxtrashed = FALSE) ) then
				outp "xchg ecx, [esp]"			'' tos= ecx; ecx= dst
				outp "xchg ecx, eax"			'' ecx= res; eax= dst
			else
				hMOV "ecx", "eax"			'' ecx= eax
				hPOP "eax"					'' restore eax
			end if

			hMOV dst, ecx					'' [eax+...] = ecx

			if( (ecxfree = FALSE) and (ecxtrashed = FALSE) ) then
				hPOP "ecx"
			end if
		end if
	end if

	if( ecxtrashed ) then
		if( (ecxfree = FALSE) and (ecxindest = FALSE) ) then
			hPOP "ecx"
		end if
	end if

end sub

'':::::
private sub _emitMODI _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst, src
    dim as integer ecxtrashed
    dim as integer eaxfree, ecxfree, edxfree
    dim as integer eaxindest, ecxindest, edxindest
    dim as integer eaxinsource, edxinsource
    dim as string eax, ecx, edx
    dim as string ostr

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

    if( dtypeTB(dvreg->dtype).size = 4 ) then
    	eax = "eax"
    	ecx = "ecx"
    	edx = "edx"
    else
    	eax = "ax"
    	ecx = "cx"
    	edx = "dx"
    end if

	ecxtrashed = FALSE

	eaxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_EAX )
	ecxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_ECX )
	edxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_EDX )

	eaxinsource = hIsRegInVreg( svreg, EMIT_REG_EAX )
	edxinsource = hIsRegInVreg( svreg, EMIT_REG_EDX )
	eaxindest = hIsRegInVreg( dvreg, EMIT_REG_EAX )
	edxindest = hIsRegInVreg( dvreg, EMIT_REG_EDX )
	ecxindest = hIsRegInVreg( dvreg, EMIT_REG_ECX )

	if( (eaxinsource) or (edxinsource) or (svreg->typ = IR_VREGTYPE_IMM) ) then
		ecxtrashed = TRUE
		if( ecxindest ) then
			hPUSH( "ecx" )
			if( dvreg->typ <> IR_VREGTYPE_REG ) then
				hPrepOperand( dvreg, ostr, FB_DATATYPE_INTEGER )
				hPUSH( ostr )
			end if
		elseif( ecxfree = FALSE ) then
			hPUSH( "ecx" )
		end if
		hMOV( ecx, src )
		src = ecx
	end if

	if( eaxindest = FALSE ) then
		if( (ecxindest) and (ecxtrashed) ) then
			if( eaxfree = FALSE ) then
				outp "xchg eax, [esp]"
			else
				hPOP "eax"
			end if
		else
			if( eaxfree = FALSE ) then
				hPUSH "eax"
			end if
			hMOV eax, dst
		end if

	else
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			hPUSH "eax"
			hMOV eax, dst
		end if
	end if

	if( edxindest ) then
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			hPUSH "edx"
		end if
	elseif( edxfree = FALSE ) then
		hPUSH "edx"
	end if

	if( symbIsSigned( dvreg->dtype ) ) then
		if( dtypeTB(dvreg->dtype).size = 4 ) then
			outp "cdq"
		else
			outp "cwd"
		end if

		ostr = "idiv " + src
		outp ostr

	else
		ostr = "xor " + edx + ", " + edx
		outp ostr

		ostr = "div " + src
		outp ostr
	end if

	hMOV eax, edx

	if( edxindest ) then
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			hPOP "edx"
		end if
	elseif( edxfree = FALSE ) then
		hPOP "edx"
	end if

	if( eaxindest = FALSE ) then
		if( ecxindest and ecxtrashed ) then
			if( dvreg->typ <> IR_VREGTYPE_REG ) then
				hPOP "ecx"					'' ecx= tos (eax)
				outp "xchg ecx, [esp]"			'' tos= ecx; ecx= dst
			end if
		end if

		hMOV dst, eax

		if( eaxfree = FALSE ) then
			hPOP "eax"
		end if

	else
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			if( (ecxfree = FALSE) and (ecxtrashed = FALSE) ) then
				outp "xchg ecx, [esp]"			'' tos= ecx; ecx= dst
				outp "xchg ecx, eax"			'' ecx= res; eax= dst
			else
				hMOV "ecx", "eax"			'' ecx= eax
				hPOP "eax"					'' restore eax
			end if

			hMOV dst, ecx					'' [eax+...] = ecx

			if( (ecxfree = FALSE) and (ecxtrashed = FALSE) ) then
				hPOP "ecx"
			end if
		end if
	end if

	if( ecxtrashed ) then
		if( (ecxfree = FALSE) and (ecxindest = FALSE) ) then
			hPOP "ecx"
		end if
	end if

end sub

'':::::
private sub hSHIFTL _
	( _
		byval op as integer, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string dst1, dst2, src, ostr, label, mnemonic
    dim as integer iseaxfree, isedxfree, isecxfree
    dim as integer eaxindest, edxindest, ecxindest
    dim as integer ofs

	''
	if( symbIsSigned( dvreg->dtype ) ) then
		if( op = AST_OP_SHL ) then
			mnemonic = "sal"
		else
			mnemonic = "sar"
		end if
	else
		if( op = AST_OP_SHL ) then
			mnemonic = "shl"
		else
			mnemonic = "shr"
		end if
	end if

    ''
	hPrepOperand64( dvreg, dst1, dst2 )
	hPrepOperand( svreg, src, FB_DATATYPE_INTEGER )

	iseaxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_EAX )
	isedxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_EDX )
	isecxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_ECX )

	eaxindest = hIsRegInVreg( dvreg, EMIT_REG_EAX )
	edxindest = hIsRegInVreg( dvreg, EMIT_REG_EDX )
	ecxindest = hIsRegInVreg( dvreg, EMIT_REG_ECX )

	hPUSH( dst2 )
	hPUSH( dst1 )
	ofs = 0

	'' load src to cl
	if( svreg->typ <> IR_VREGTYPE_IMM ) then
		if( (svreg->typ <> IR_VREGTYPE_REG) or (svreg->reg <> EMIT_REG_ECX) ) then
			'' handle src < dword
			if( symbGetDataSize( svreg->dtype ) <> FB_INTEGERSIZE ) then
				'' if it's not a reg, the right size was already set at the hPrepOperand() above
				if( svreg->typ = IR_VREGTYPE_REG ) then
					src = *hGetRegName( FB_DATATYPE_INTEGER, svreg->reg )
				end if
			end if

			if( isecxfree = FALSE ) then
				if( ecxindest and dvreg->typ = IR_VREGTYPE_REG ) then
					hMOV( "ecx", src )
					isecxfree = TRUE
				else
					hPUSH( src )
					outp "xchg ecx, [esp]"
					ofs += 4
				end if
			else
				hMOV( "ecx", src )
			end if
		else
			isecxfree = TRUE
		end if
	end if

	'' load dst1 to eax
	if( eaxindest ) then
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			outp "xchg eax, [esp+" + str( ofs+0 ) + "]"
		else
			outp "mov eax, [esp+" + str( ofs+0 ) + "]"
		end if
	else
		if( iseaxfree = FALSE ) then
			outp "xchg eax, [esp+" + str( ofs+0 ) + "]"
		else
			outp "mov eax, [esp+" + str( ofs+0 ) + "]"
		end if
	end if

	'' load dst2 to edx
	if( edxindest ) then
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			outp "xchg edx, [esp+" + str( ofs+4 ) + "]"
		else
			outp "mov edx, [esp+" + str( ofs+4 ) + "]"
		end if
	else
		if( isedxfree = FALSE ) then
			outp "xchg edx, [esp+" + str( ofs+4 ) + "]"
		else
			outp "mov edx, [esp+" + str( ofs+4 ) + "]"
		end if
	end if

	'' if src is not an imm, use cl and check for the x86 glitches
	if( svreg->typ <> IR_VREGTYPE_IMM ) then
		label = *hMakeTmpStr( )

		if( op = AST_OP_SHL ) then
			outp "shld edx, eax, cl"
			outp mnemonic + " eax, cl"
		else
			outp "shrd eax, edx, cl"
			outp mnemonic + " edx, cl"
		end if

		outp "test cl, 32"
		hBRANCH( "jz", label )

		if( op = AST_OP_SHL ) then
			outp "mov edx, eax"
			outp "xor eax, eax"
		else
			outp "mov eax, edx"
			if( symbIsSigned( dvreg->dtype ) ) then
				outp "sar edx, 31"
			else
				outp "xor edx, edx"
			end if
		end if

		hLABEL( label )

		if( isecxfree = FALSE ) then
			hPOP "ecx"
		end if

	'' immediate
	else

		if( svreg->value < 32 ) then
			if( op = AST_OP_SHL ) then
				outp "shld edx, eax, " + src
				outp mnemonic + " eax, " + src
			else
				outp "shrd eax, edx, " + src
				outp mnemonic + " edx, " + src
			end if

		elseif( svreg->value > 32 ) then
			src = str( svreg->value - 32 )
			if( op = AST_OP_SHL ) then
				outp "mov edx, eax"
				outp "xor eax, eax"
				outp "shl edx, " + src
			else
				outp "mov eax, edx"
				if( symbIsSigned( dvreg->dtype ) ) then
					outp "sar edx, 31"
					outp "sar eax, " + src
				else
					outp "xor edx, edx"
					outp "shr eax, " + src
				end if
			end if

		'' src = 32, just swap
		else
			if( op = AST_OP_SHL ) then
				outp "mov edx, eax"
				outp "xor eax, eax"
			else
				outp "mov eax, edx"
				if( symbIsSigned( dvreg->dtype ) ) then
					outp "sar edx, 31"
				else
					outp "xor edx, edx"
				end if
			end if
		end if
	end if

	'' save dst2
	if( edxindest ) then
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			outp "xchg edx, [esp+4]"
		else
			outp "mov [esp+4], edx"
		end if
	else
		if( isedxfree = FALSE ) then
			outp "xchg edx, [esp+4]"
		else
			outp "mov [esp+4], edx"
		end if
	end if

	'' save dst1
	if( eaxindest ) then
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			outp "xchg eax, [esp+0]"
		else
			outp "mov [esp+0], eax"
		end if
	else
		if( iseaxfree = FALSE ) then
			outp "xchg eax, [esp+0]"
		else
			outp "mov [esp+0], eax"
		end if
	end if

	hPOP( dst1 )
	hPOP( dst2 )

end sub

'':::::
private sub hSHIFTI _
	( _
		byval op as integer, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim eaxpreserved as integer, ecxpreserved as integer
    dim eaxfree as integer, ecxfree as integer
    dim reg as integer
    dim ecxindest as integer
    dim as string ostr, dst, src, tmp, mnemonic

	''
	if( symbIsSigned( dvreg->dtype ) ) then
		if( op = AST_OP_SHL ) then
			mnemonic = "sal"
		else
			mnemonic = "sar"
		end if
	else
		if( op = AST_OP_SHL ) then
			mnemonic = "shl"
		else
			mnemonic = "shr"
		end if
	end if

    ''
	hPrepOperand( dvreg, dst )

	ecxindest = FALSE
	eaxpreserved = FALSE
	ecxpreserved = FALSE

	if( svreg->typ = IR_VREGTYPE_IMM ) then
		hPrepOperand( svreg, src )
		tmp = dst

	else
		eaxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_EAX )
		ecxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_ECX )

		if( svreg->typ = IR_VREGTYPE_REG ) then
			reg = svreg->reg
		else
			reg = INVALID
		end if

        ecxindest = hIsRegInVreg( dvreg, EMIT_REG_ECX )

		'' ecx in destine?
		if( ecxindest ) then
			'' preserve
			hPUSH "ecx"
			'' not a reg?
			if( dvreg->typ <> IR_VREGTYPE_REG ) then
				hPrepOperand( dvreg, ostr, FB_DATATYPE_INTEGER )
				hPUSH ostr
			end if

		'' ecx not free?
		elseif( (reg <> EMIT_REG_ECX) and (ecxfree = FALSE) ) then
			ecxpreserved = TRUE
			hPUSH "ecx"
		end if

		'' source not a reg?
		if( svreg->typ <> IR_VREGTYPE_REG ) then
			hPrepOperand( svreg, ostr, FB_DATATYPE_BYTE )
			hMOV "cl", ostr
		else
			'' source not ecx?
			if( reg <> EMIT_REG_ECX ) then
				hMOV "ecx", rnameTB(dtypeTB(FB_DATATYPE_INTEGER).rnametb, reg)
			end if
		end if

		'' load ecx to a tmp?
		if( ecxindest ) then
			'' tmp not free?
			if( eaxfree = FALSE ) then
				eaxpreserved = TRUE
				outp "xchg eax, [esp]"		'' eax= dst; push eax
			else
				hPOP "eax"				'' eax= dst; pop tos
			end if

			tmp = rnameTB(dtypeTB(dvreg->dtype).rnametb, EMIT_REG_EAX )

		else
			tmp = dst
		end if

		src = "cl"

	end if

	ostr = mnemonic + " " + tmp + COMMA + src
	outp ostr

	if( ecxindest ) then
		if( dvreg->typ <> IR_VREGTYPE_REG ) then
			hPOP "ecx"
			if( eaxpreserved ) then
				outp "xchg ecx, [esp]"		'' ecx= tos; tos= eax
			end if
		end if
		hMOV dst, rnameTB(dtypeTB(dvreg->dtype).rnametb, EMIT_REG_EAX)
	end if

	if( eaxpreserved ) then
		hPOP "eax"
	end if

	if( ecxpreserved ) then
		hPOP "ecx"
	end if

end sub

'':::::
private sub _emitSHLL _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	hSHIFTL( AST_OP_SHL, dvreg, svreg )

end sub

'':::::
private sub _emitSHLI _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	hSHIFTI( AST_OP_SHL, dvreg, svreg )

end sub

'':::::
private sub _emitSHRL _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	hSHIFTL( AST_OP_SHR, dvreg, svreg )

end sub

'':::::
private sub _emitSHRI _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	hSHIFTI( AST_OP_SHR, dvreg, svreg )

end sub

'':::::
private sub _emitANDL _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim dst1 as string, dst2 as string, src1 as string, src2 as string
    dim ostr as string

	hPrepOperand64( dvreg, dst1, dst2 )
	hPrepOperand64( svreg, src1, src2 )

	ostr = "and " + dst1 + COMMA + src1
	outp ostr

	ostr = "and " + dst2 + COMMA + src2
	outp ostr

end sub

'':::::
private sub _emitANDI _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim dst as string, src as string
    dim ostr as string

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	ostr = "and " + dst + COMMA + src
	outp ostr

end sub

'':::::
private sub _emitORL _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim dst1 as string, dst2 as string, src1 as string, src2 as string
    dim ostr as string

	hPrepOperand64( dvreg, dst1, dst2 )
	hPrepOperand64( svreg, src1, src2 )

	ostr = "or " + dst1 + COMMA + src1
	outp ostr

	ostr = "or " + dst2 + COMMA + src2
	outp ostr

end sub

'':::::
private sub _emitORI _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim dst as string, src as string
    dim ostr as string

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	ostr = "or " + dst + COMMA + src
	outp ostr

end sub

'':::::
private sub _emitXORL _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim dst1 as string, dst2 as string, src1 as string, src2 as string
    dim ostr as string

	hPrepOperand64( dvreg, dst1, dst2 )
	hPrepOperand64( svreg, src1, src2 )

	ostr = "xor " + dst1 + COMMA + src1
	outp ostr

	ostr = "xor " + dst2 + COMMA + src2
	outp ostr

end sub

'':::::
private sub _emitXORI _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim dst as string, src as string
    dim ostr as string

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	ostr = "xor " + dst + COMMA + src
	outp ostr

end sub

'':::::
private sub _emitEQVL _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim dst1 as string, dst2 as string, src1 as string, src2 as string
    dim ostr as string

	hPrepOperand64( dvreg, dst1, dst2 )
	hPrepOperand64( svreg, src1, src2 )

	ostr = "xor " + dst1 + COMMA + src1
	outp ostr

	ostr = "xor " + dst2 + COMMA + src2
	outp ostr

	ostr = "not " + dst1
	outp ostr

	ostr = "not " + dst2
	outp ostr

end sub

'':::::
private sub _emitEQVI _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim dst as string, src as string
    dim ostr as string

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	ostr = "xor " + dst + COMMA + src
	outp ostr

	ostr = "not " + dst
	outp ostr

end sub

'':::::
private sub _emitIMPL _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim dst1 as string, dst2 as string, src1 as string, src2 as string
    dim ostr as string

	hPrepOperand64( dvreg, dst1, dst2 )
	hPrepOperand64( svreg, src1, src2 )

	ostr = "not " + dst1
	outp ostr

	ostr = "not " + dst2
	outp ostr

	ostr = "or " + dst1 + COMMA + src1
	outp ostr

	ostr = "or " + dst2 + COMMA + src2
	outp ostr

end sub

'':::::
private sub _emitIMPI _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim dst as string, src as string
    dim ostr as string

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	ostr = "not " + dst
	outp ostr

	ostr = "or " + dst + COMMA + src
	outp ostr

end sub

'':::::
private sub _emitATN2 _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim src as string
    dim ostr as string

	hPrepOperand( svreg, src )

	if( svreg->typ <> IR_VREGTYPE_REG ) then
		ostr = "fld " + src
		outp ostr
	else
		outp "fxch"
	end if
	outp "fpatan"

end sub

'':::::
private sub _emitPOW _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	dim src as string
	dim ostr as string

	hPrepOperand( svreg, src )

	if( svreg->typ <> IR_VREGTYPE_REG ) then
		ostr = "fld " + src
		outp ostr
		outp "fxch"
	end if

	outp "fabs"
	outp "fyl2x"
	outp "fld st(0)"
	outp "frndint"
	outp "fsub st(1), st(0)"
	outp "fxch"
	outp "f2xm1"
	outp "fld1"
	outp "faddp"
	outp "fscale"
	outp "fstp st(1)"

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' relational
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
private sub hCMPL _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval mnemonic as zstring ptr, _
		byval rev_mnemonic as zstring ptr, _
		byval usg_mnemonic as zstring ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr, _
		byval isinverse as integer = FALSE _
	) static

    dim as string dst1, dst2, src1, src2, rname, ostr, lname, falselabel

	hPrepOperand64( dvreg, dst1, dst2 )
	hPrepOperand64( svreg, src1, src2 )

	if( label = NULL ) then
		lname = *hMakeTmpStr( )
	else
		lname = *symbGetMangledName( label )
	end if

	'' check high
	ostr = "cmp " + dst2 + COMMA + src2
	outp ostr

	falselabel = *hMakeTmpStr( )

	'' set the boolean result?
	if( rvreg <> NULL ) then
		hPrepOperand( rvreg, rname )
		hMOV( rname, "-1" )
	end if

	ostr = "j" + *mnemonic
	if( isinverse = FALSE ) then
		hBRANCH( ostr, lname )
	else
		hBRANCH( ostr, falselabel )
	end if

	if( len( *rev_mnemonic ) > 0 ) then
		ostr = "j" + *rev_mnemonic
		hBRANCH( ostr, falselabel )
	end if

	'' check low
	ostr = "cmp " + dst1 + COMMA + src1
	outp ostr

	ostr = "j" + *usg_mnemonic
	hBRANCH( ostr, lname )

	hLabel( falselabel )

	if( rvreg <> NULL ) then
		ostr = "xor " + rname + COMMA + rname
		outp ostr

		hLabel( lname )
	end if

end sub

'':::::
private sub hCMPI _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval mnemonic as zstring ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

    dim as string rname, rname8, dst, src, ostr, lname
    dim as integer isedxfree, dotest

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	if( label = NULL ) then
		lname = *hMakeTmpStr( )
	else
		lname = *symbGetMangledName( label )
	end if

	'' optimize "cmp" to "test"
	dotest = FALSE
	if( (svreg->typ = IR_VREGTYPE_IMM) and (dvreg->typ = IR_VREGTYPE_REG) ) then
		if( svreg->value = 0 ) then
			dotest = TRUE
		end if
	end if

	if( dotest ) then
		ostr = "test " + dst + COMMA + dst
		outp ostr
	else
		ostr = "cmp " + dst + COMMA + src
		outp ostr
	end if

	'' no result to be set? just branch
	if( rvreg = NULL ) then
		ostr = "j" + *mnemonic
		hBRANCH( ostr, lname )
		exit sub
	end if

	hPrepOperand( rvreg, rname )

	'' can it be optimized?
	if( (env.clopt.cputype >= FB_CPUTYPE_486) and (rvreg->typ = IR_VREGTYPE_REG) ) then

		rname8 = *hGetRegName( FB_DATATYPE_BYTE, rvreg->reg )

		'' handle EDI and ESI
		if( (rvreg->reg = EMIT_REG_ESI) or (rvreg->reg = EMIT_REG_EDI) ) then

			isedxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_EDX )
			if( isedxfree = FALSE ) then
				ostr = "xchg edx, " + rname
				outp ostr
			end if

			ostr = "set" + *mnemonic + " dl"
			outp ostr

			if( isedxfree = FALSE ) then
				ostr = "xchg edx, " + rname
				outp ostr
			else
				hMOV rname, "edx"
			end if

		else
			ostr = "set" + *mnemonic + " " + rname8
			outp ostr
		end if

		'' convert 1 to -1 (TRUE in QB/FB)
		ostr = "shr " + rname + ", 1"
		outp ostr

		ostr = "sbb " + rname + COMMA + rname
		outp ostr

	'' old (and slow) boolean set
	else

		ostr = "mov " + rname + ", -1"
		outp ostr

		ostr = "j" + *mnemonic
		hBRANCH( ostr, lname )

		ostr = "xor " + rname + COMMA + rname
		outp ostr

		hLabel( lname )
	end if

end sub

'':::::
private sub hCMPF _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval mnemonic as zstring ptr, _
		byval mask as zstring ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	dim as string rname, rname8, dst, src, ostr, lname
    dim as integer iseaxfree, isedxfree

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src )

	if( label = NULL ) then
		lname = *hMakeTmpStr( )
	else
		lname = *symbGetMangledName( label )
	end if

	'' do comp
	if( svreg->typ = IR_VREGTYPE_REG ) then
		outp "fcompp"
	else
		'' can it be optimized to ftst?
		if( symbGetDataClass( svreg->dtype ) = FB_DATACLASS_FPOINT ) then
			ostr = "fcomp " + src
			outp ostr
		else
			ostr = "ficomp " + src
			outp ostr
		end if
	end if

    iseaxfree = TRUE
    if( rvreg <> NULL ) then
    	if( rvreg->reg <> EMIT_REG_EAX ) then
    		iseaxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_EAX )
    		if( iseaxfree = FALSE ) then
    			hPUSH( "eax" )
    		end if
    	end if
	end if

    '' load fpu flags
    outp "fnstsw ax"
	if( len( *mask ) > 0 ) then
		ostr = "test ah, " + *mask
		outp ostr
	else
		outp "sahf"
	end if

	if( iseaxfree = FALSE ) then
		hPOP( "eax" )
	end if

    '' no result to be set? just branch
    if( rvreg = NULL ) then
    	ostr = "j" + *mnemonic
    	hBRANCH( ostr, lname )
    	exit sub
    end if

    hPrepOperand( rvreg, rname )

	'' can it be optimized?
	if( env.clopt.cputype >= FB_CPUTYPE_486 ) then
		rname8 = *hGetRegName( FB_DATATYPE_BYTE, rvreg->reg )

		'' handle EDI and ESI
		if( (rvreg->reg = EMIT_REG_ESI) or (rvreg->reg = EMIT_REG_EDI) ) then

			isedxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_EDX )
			if( isedxfree = FALSE ) then
				ostr = "xchg edx, " + rname
				outp ostr
			end if

			ostr = "set" + *mnemonic + (TABCHAR + "dl")
			outp ostr

			if( isedxfree = FALSE ) then
				ostr = "xchg edx, " + rname
				outp ostr
			else
				hMOV rname, "edx"
			end if
		else
			ostr = "set" + *mnemonic + " " + rname8
			outp ostr
		end if

		'' convert 1 to -1 (TRUE in QB/FB)
		ostr = "shr " + rname + ", 1"
		outp ostr

		ostr = "sbb " + rname + COMMA + rname
		outp ostr

	'' old (and slow) boolean set
	else
    	ostr = "mov " + rname + ", -1"
    	outp ostr

    	ostr = "j" + *mnemonic
    	hBRANCH( ostr, lname )

		ostr = "xor " + rname + COMMA + rname
		outp ostr

		hLabel( lname )
	end if

end sub

'':::::
private sub _emitCGTL _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	dim jmp as string, rjmp as string

	if( symbIsSigned( dvreg->dtype ) ) then
		jmp = "g"
		rjmp = "l"
	else
		jmp = "a"
		rjmp = "b"
	end if

	hCMPL( rvreg, label, jmp, rjmp, "a", dvreg, svreg )

end sub

'':::::
private sub _emitCGTI _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	dim jmp as string

	if( symbIsSigned( dvreg->dtype ) ) then
		jmp = "g"
	else
		jmp = "a"
	end if

	hCMPI( rvreg, label, jmp, dvreg, svreg )

end sub

'':::::
private sub _emitCGTF _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	hCMPF( rvreg, label, "z", "0b01000001", dvreg, svreg )

end sub

'':::::
private sub _emitCLTL _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	dim jmp as string, rjmp as string

	if( symbIsSigned( dvreg->dtype ) ) then
		jmp = "l"
		rjmp = "g"
	else
		jmp = "b"
		rjmp = "a"
	end if

	hCMPL( rvreg, label, jmp, rjmp, "b", dvreg, svreg )

end sub

'':::::
private sub _emitCLTI _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	dim jmp as string

	if( symbIsSigned( dvreg->dtype ) ) then
		jmp = "l"
	else
		jmp = "b"
	end if

	hCMPI( rvreg, label, jmp, dvreg, svreg )

end sub

'':::::
private sub _emitCLTF _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	hCMPF( rvreg, label, "nz", "0b00000001", dvreg, svreg )

end sub

'':::::
private sub _emitCEQL _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	hCMPL( rvreg, label, "ne", "", "e", dvreg, svreg, TRUE )

end sub

'':::::
private sub _emitCEQI _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	hCMPI( rvreg, label, "e", dvreg, svreg )

end sub

'':::::
private sub _emitCEQF _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	hCMPF( rvreg, label, "nz", "0b01000000", dvreg, svreg )

end sub

'':::::
private sub _emitCNEL _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	hCMPL( rvreg, label, "ne", "", "ne", dvreg, svreg )

end sub

'':::::
private sub _emitCNEI _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	hCMPI( rvreg, label, "ne", dvreg, svreg )

end sub

'':::::
private sub _emitCNEF _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	hCMPF( rvreg, label, "z", "0b01000000", dvreg, svreg )

end sub

'':::::
private sub _emitCLEL _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	dim jmp as string, rjmp as string

	if( symbIsSigned( dvreg->dtype ) ) then
		jmp = "l"
		rjmp = "g"
	else
		jmp = "b"
		rjmp = "a"
	end if

	hCMPL( rvreg, label, jmp, rjmp, "be", dvreg, svreg )

end sub

'':::::
private sub _emitCLEI _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	dim jmp as string

	if( symbIsSigned( dvreg->dtype ) ) then
		jmp = "le"
	else
		jmp = "be"
	end if

	hCMPI( rvreg, label, jmp, dvreg, svreg )

end sub


'':::::
private sub _emitCLEF _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	hCMPF( rvreg, label, "nz", "0b01000001", dvreg, svreg )

end sub


'':::::
private sub _emitCGEL _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	dim jmp as string, rjmp as string

	if( symbIsSigned( dvreg->dtype ) ) then
		jmp = "g"
		rjmp = "l"
	else
		jmp = "a"
		rjmp = "b"
	end if

	hCMPL( rvreg, label, jmp, rjmp, "ae", dvreg, svreg )

end sub

'':::::
private sub _emitCGEI _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	dim jmp as string

	if( symbIsSigned( dvreg->dtype ) ) then
		jmp = "ge"
	else
		jmp = "ae"
	end if

	hCMPI( rvreg, label, jmp, dvreg, svreg )

end sub

'':::::
private sub _emitCGEF _
	( _
		byval rvreg as IRVREG ptr, _
		byval label as FBSYMBOL ptr, _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	hCMPF( rvreg, label, "ae", "", dvreg, svreg )

end sub


''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' unary ops
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
private sub _emitNEGL _
	( _
		byval dvreg as IRVREG ptr _
	) static

    dim dst1 as string, dst2 as string
    dim ostr as string

	hPrepOperand64( dvreg, dst1, dst2 )

	ostr = "neg " + dst1
	outp ostr

	ostr = "adc " + dst2 + ", 0"
	outp ostr

	ostr = "neg " + dst2
	outp ostr

end sub

'':::::
private sub _emitNEGI _
	( _
		byval dvreg as IRVREG ptr _
	) static

    dim dst as string
    dim ostr as string

	hPrepOperand( dvreg, dst )

	ostr = "neg " + dst
	outp ostr

end sub

'':::::
private sub _emitNEGF _
	( _
		byval dvreg as IRVREG ptr _
	) static

	outp "fchs"

end sub

'':::::
private sub _emitNOTL _
	( _
		byval dvreg as IRVREG ptr _
	) static

    dim dst1 as string, dst2 as string
    dim ostr as string

	hPrepOperand64( dvreg, dst1, dst2 )

	ostr = "not " + dst1
	outp ostr

	ostr = "not " + dst2
	outp ostr

end sub

'':::::
private sub _emitNOTI _
	( _
		byval dvreg as IRVREG ptr _
	) static

    dim dst as string
    dim ostr as string

	hPrepOperand( dvreg, dst )

	ostr = "not " + dst
	outp ostr

end sub

'':::::
private sub _emitABSL _
	( _
		byval dvreg as IRVREG ptr _
	) static

    dim dst1 as string, dst2 as string
    dim reg as integer, isfree as integer, rname as string
    dim ostr as string

	hPrepOperand64( dvreg, dst1, dst2 )

	reg = hFindRegNotInVreg( dvreg )
	rname = *hGetRegName( FB_DATATYPE_INTEGER, reg )

	isfree = hIsRegFree( FB_DATACLASS_INTEGER, reg )

	if( isfree = FALSE ) then
		hPUSH( rname )
	end if

	hMOV( rname, dst2 )

	ostr = "sar " + rname + ", 31"
	outp ostr

	ostr = "xor " + dst1 + COMMA + rname
	outp ostr

	ostr = "xor " + dst2 + COMMA + rname
	outp ostr

	ostr = "sub " + dst1 + COMMA + rname
	outp ostr

	ostr = "sbb " + dst2 + COMMA + rname
	outp ostr

	if( isfree = FALSE ) then
		hPOP( rname )
	end if

end sub

'':::::
private sub _emitABSI _
	( _
		byval dvreg as IRVREG ptr _
	) static

    dim dst as string
    dim reg as integer, isfree as integer, rname as string, bits as integer
    dim ostr as string

	hPrepOperand( dvreg, dst )

	reg = hFindRegNotInVreg( dvreg )
	rname = *hGetRegName( dvreg->dtype, reg )

	isfree = hIsRegFree( FB_DATACLASS_INTEGER, reg )

	if( isfree = FALSE ) then
		hPUSH( rname )
	end if

	bits = (dtypeTB(dvreg->dtype).size * 8)-1

	hMOV( rname, dst )

	ostr = "sar " + rname + COMMA + str( bits )
	outp ostr

	ostr = "xor " + dst + COMMA + rname
	outp ostr

	ostr = "sub " + dst + COMMA + rname
	outp ostr

	if( isfree = FALSE ) then
		hPOP( rname )
	end if

end sub

'':::::
private sub _emitABSF _
	( _
		byval dvreg as IRVREG ptr _
	) static

	outp "fabs"

end sub

'':::::
private sub _emitSGNL _
	( _
		byval dvreg as IRVREG ptr _
	) static

    dim dst1 as string, dst2 as string
    dim ostr as string
    dim label1 as string, label2 as string

	hPrepOperand64( dvreg, dst1, dst2 )

	label1 = *hMakeTmpStr( )
	label2 = *hMakeTmpStr( )

	ostr = "cmp " + dst2 + ", 0"
	outp ostr
	hBRANCH( "jne", label1 )

	ostr = "cmp " + dst1 + ", 0"
	outp ostr
	hBRANCH( "je", label2 )

	hLABEL( label1 )
	hMOV( dst1, "1" )
	hMOV( dst2, "0" )
	hBRANCH( "jg", label2 )
	hMOV( dst1, "-1" )
	hMOV( dst2, "-1" )

	hLABEL( label2 )

end sub

'':::::
private sub _emitSGNI _
	( _
		byval dvreg as IRVREG ptr _
	) static

    dim dst as string
    dim label as string
    dim ostr as string

	hPrepOperand( dvreg, dst )

	label = *hMakeTmpStr( )

	ostr = "cmp " + dst + ", 0"
	outp ostr

	hBRANCH( "je", label )
	hMOV( dst, "1" )
	hBRANCH( "jg", label )
	hMOV( dst, "-1" )

	hLABEL( label )

end sub

'':::::
private sub _emitSGNF _
	( _
		byval dvreg as IRVREG ptr _
	) static

	'' hack! floating-point SGN is done by a rtlib function, called by AST

end sub

'':::::
private sub _emitSIN _
	( _
		byval dvreg as IRVREG ptr _
	) static

	outp "fsin"

end sub

'':::::
private sub _emitASIN _
	( _
		byval dvreg as IRVREG ptr _
	) static

	'' asin( x ) = atn( sqr( (x*x) / (1-x*x) ) )
	outp "fld st(0)"
	outp "fmulp"
	outp "fld st(0)"
	outp "fld1"
	outp "fsubrp"
    outp "fdivp"
    outp "fsqrt"
    outp "fld1"
    outp "fpatan"

end sub

'':::::
private sub _emitCOS _
	( _
		byval dvreg as IRVREG ptr _
	) static

	outp "fcos"

end sub

'':::::
private sub _emitACOS _
	( _
		byval dvreg as IRVREG ptr _
	) static

	'' acos( x ) = atn( sqr( (1-x*x) / (x*x) ) )
	outp "fld st(0)"
    outp "fmulp"
	outp "fld st(0)"
    outp "fld1"
	outp "fsubrp"
	outp "fdivrp"
	outp "fsqrt"
	outp "fld1"
	outp "fpatan"

end sub

'':::::
private sub _emitTAN _
	( _
		byval dvreg as IRVREG ptr _
	) static

	outp "fptan"
	outp "fstp st(0)"

end sub

'':::::
private sub _emitATAN _
	( _
		byval dvreg as IRVREG ptr _
	) static

	outp "fld1"
	outp "fpatan"

end sub

'':::::
private sub _emitSQRT _
	( _
		byval dvreg as IRVREG ptr _
	) static

	outp "fsqrt"

end sub

'':::::
private sub _emitLOG _
	( _
		byval dvreg as IRVREG ptr _
	) static

	'' log( x ) = log2( x ) / log2( e ).

	outp "fld1"
	outp "fxch"
	outp "fyl2x"
	outp "fldl2e"
	outp "fdivp"

end sub

'':::::
private sub _emitFLOOR _
	( _
		byval dvreg as IRVREG ptr _
	) static

	dim as integer reg, isfree
	dim as string rname, ostr

	reg = hFindFreeReg( FB_DATACLASS_INTEGER )
	rname = *hGetRegName( FB_DATATYPE_INTEGER, reg )

	isfree = hIsRegFree( FB_DATACLASS_INTEGER, reg )

	if( isfree = FALSE ) then
		hPUSH( rname )
	end if

	outp "sub esp, 4"
	outp "fnstcw [esp]"
	hMOV rname, "[esp]"
	ostr = "and " + rname + ", 0b1111001111111111"
	outp ostr
	ostr = "or " + rname +  ", 0b0000010000000000"
	outp ostr
	hPUSH rname
	outp "fldcw [esp]"
	outp "add esp, 4"
	outp "frndint"
	outp "fldcw [esp]"
	outp "add esp, 4"

	if( isfree = FALSE ) then
		hPOP( rname )
	end if

end sub

'':::::
private sub _emitXchgTOS _
	( _
		byval svreg as IRVREG ptr _
	) static

    dim as string src
    dim as string ostr

	hPrepOperand( svreg, src )

	ostr = "fxch " + src
	outp( ostr )

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' stack
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
private sub _emitPUSHL _
	( _
		byval svreg as IRVREG ptr, _
		byval unused as integer _
	) static

    dim src1 as string, src2 as string
    dim ostr as string

	hPrepOperand64( svreg, src1, src2 )

	ostr = "push " + src2
	outp ostr

	ostr = "push " + src1
	outp ostr

end sub

'':::::
private sub _emitPUSHI _
	( _
		byval svreg as IRVREG ptr, _
		byval unused as integer _
	) static

    dim src as string, sdsize as integer
    dim ostr as string

	hPrepOperand( svreg, src )

	sdsize = symbGetDataSize( svreg->dtype )

	if( svreg->typ = IR_VREGTYPE_REG ) then
		if( sdsize < FB_INTEGERSIZE ) then
			src = *hGetRegName( FB_DATATYPE_INTEGER, svreg->reg )
		end if
	else
		if( sdsize < FB_INTEGERSIZE ) then
			'' !!!FIXME!!! assuming it's okay to push over the var if's not dword aligned
			hPrepOperand( svreg, src, FB_DATATYPE_INTEGER )
		end if
	end if

	ostr = "push " + src
	outp ostr

end sub

'':::::
private sub _emitPUSHF _
	( _
		byval svreg as IRVREG ptr, _
		byval unused as integer _
	) static

    dim src as string, sdsize as integer
    dim ostr as string

	hPrepOperand( svreg, src )

	sdsize = symbGetDataSize( svreg->dtype )

	if( svreg->typ <> IR_VREGTYPE_REG ) then
		if( svreg->dtype = FB_DATATYPE_SINGLE ) then
			ostr = "push " + src
			outp ostr
		else
			hPrepOperand( svreg, src, FB_DATATYPE_INTEGER, 4 )
			ostr = "push " + src
			outp ostr

    		hPrepOperand( svreg, src, FB_DATATYPE_INTEGER, 0 )
			ostr = "push " + src
			outp ostr
		end if
	else
		ostr = "sub esp," + str( sdsize )
		outp ostr

		ostr = "fstp " + dtypeTB(svreg->dtype).mname + " [esp]"
		outp ostr
	end if

end sub

'':::::
private sub _emitPUSHUDT _
	( _
		byval svreg as IRVREG ptr, _
		byval sdsize as integer _
	) static

    dim as integer ofs
    dim as string ostr, src

	'' !!!FIXME!!! assuming it's okay to push over the UDT if's not dword aligned
	if( sdsize < FB_INTEGERSIZE ) then
		sdsize = FB_INTEGERSIZE
	end if

	ofs = sdsize - FB_INTEGERSIZE
	do while( ofs >= 0 )
		hPrepOperand( svreg, src, FB_DATATYPE_INTEGER, ofs )
		ostr = "push " + src
		outp( ostr )
		ofs -= FB_INTEGERSIZE
	loop

end sub

'':::::
private sub _emitPOPL _
	( _
		byval dvreg as IRVREG ptr, _
		byval unused as integer _
	) static

    dim dst1 as string, dst2 as string
    dim ostr as string

	hPrepOperand64( dvreg, dst1, dst2 )

	ostr = "pop " + dst1
	outp ostr

	ostr = "pop " + dst2
	outp ostr

end sub

'':::::
private sub _emitPOPI _
	( _
		byval dvreg as IRVREG ptr, _
		byval unused as integer _
	) static

    dim as string dst, ostr
    dim as integer dsize

	hPrepOperand( dvreg, dst )

	dsize = symbGetDataSize( dvreg->dtype )

	if( dsize = FB_INTEGERSIZE ) then
		ostr = "pop " + dst
		outp ostr

	else
		if( dvreg->typ = IR_VREGTYPE_REG ) then
			dst = *hGetRegName( FB_DATATYPE_INTEGER, dvreg->reg )
			ostr = "pop " + dst
			outp ostr
		else

			outp "xchg eax, [esp]"

			if( dsize = 1 ) then
				hMOV dst, "al"
			else
				hMOV dst, "ax"
			end if

			if( hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_EAX ) = FALSE ) then
				hPOP "eax"
			else
				outp "add esp, 4"
			end if
		end if

	end if

end sub

'':::::
private sub _emitPOPF _
	( _
		byval dvreg as IRVREG ptr, _
		byval unused as integer _
	) static

    dim as string dst, ostr
    dim as integer dsize

	hPrepOperand( dvreg, dst )

	dsize = symbGetDataSize( dvreg->dtype )

	if( dvreg->typ <> IR_VREGTYPE_REG ) then
		if( dvreg->dtype = FB_DATATYPE_SINGLE ) then
			ostr = "pop " + dst
			outp ostr
		else
			hPrepOperand( dvreg, dst, FB_DATATYPE_INTEGER, 0 )
			ostr = "pop " + dst
			outp ostr

			hPrepOperand( dvreg, dst, FB_DATATYPE_INTEGER, 4 )
			ostr = "pop " + dst
			outp ostr
		end if
	else
		ostr = "fld " + dtypeTB(dvreg->dtype).mname + " [esp]"
		outp ostr

		ostr = "add esp," + str( dsize )
		outp ostr
	end if

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' addressing
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
private sub _emitADDROF _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	dim as string dst, src
	dim as string ostr

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src, , , , FALSE )

	ostr = "lea " + dst + ", " + src
	outp ostr

end sub

'':::::
private sub _emitDEREF _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr _
	) static

	dim as string dst, src
	dim as string ostr

	hPrepOperand( dvreg, dst )
	hPrepOperand( svreg, src, FB_DATATYPE_UINT )

	ostr = "mov " + dst + COMMA + src
	outp ostr

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' memory
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
private sub hMemMoveRep _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr, _
		byval bytes as integer _
	) static

	dim as string dst, src
	dim as string ostr
	dim as integer ecxfree, edifree, esifree
	dim as integer ediinsrc, ecxinsrc

	hPrepOperand( dvreg, dst, , , , FALSE )
	hPrepOperand( svreg, src, , , , FALSE )

	ecxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_ECX )
	edifree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_ESI )
	esifree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_EDI )

	ediinsrc = hIsRegInVreg( svreg, EMIT_REG_EDI )
	ecxinsrc = hIsRegInVreg( svreg, EMIT_REG_ECX )

	if( ecxfree = FALSE ) then
		hPUSH( "ecx" )
	end if
	if( edifree = FALSE ) then
		hPUSH( "edi" )
	end if
	if( esifree = FALSE ) then
		hPUSH( "esi" )
	end if

	if( ediinsrc = FALSE ) then
		ostr = "lea edi, " + dst
		outp ostr
	else
		if( ecxinsrc ) then
			hPUSH( "ecx" )
		end if
		ostr = "lea ecx, " + dst
		outp ostr
		if( ecxinsrc ) then
			outp "xchg ecx, [esp]"
		end if
	end if

	ostr = "lea esi, " + src
	outp ostr

	if( ediinsrc ) then
		if( ecxinsrc = FALSE ) then
			hMOV( "edi", "ecx" )
		else
			hPOP( "edi" )
		end if
	end if

	if( bytes > 4 ) then
		ostr = "mov ecx, " + str( cunsg(bytes) \ 4 )
		outp ostr
		outp "rep movsd"

	elseif( bytes = 4 ) then
		outp "mov ecx, [esi]"
		outp "mov [edi], ecx"
		if( (bytes and 3) > 0 ) then
			outp "add esi, 4"
			outp "add edi, 4"
		end if
	end if

		bytes and= 3
	if( bytes > 0 ) then
		if( bytes >= 2 ) then
			outp "mov cx, [esi]"
			outp "mov [edi], cx"
			if( bytes = 3 ) then
				outp "add esi, 2"
				outp "add edi, 2"
			end if
		end if

		if( (bytes and 1) <> 0 ) then
			outp "mov cl, [esi]"
			outp "mov [edi], cl"
		end if
	end if

	if( esifree = FALSE ) then
		hPOP( "esi" )
	end if
	if( edifree = FALSE ) then
		hPOP( "edi" )
	end if
	if( ecxfree = FALSE ) then
		hPOP( "ecx" )
	end if

end sub

'':::::
private sub hMemMoveBlk _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr, _
		byval bytes as integer _
	) static

	dim as string dst, src, aux
	dim as integer i, ofs, reg, isfree

	reg = hFindRegNotInVreg( dvreg )

	'' no free regs left?
	if( hIsRegInVreg( svreg, reg ) ) then
		hMemMoveRep( dvreg, svreg, bytes )
		exit sub
	end if

	aux = *hGetRegName( FB_DATATYPE_INTEGER, reg )

	isfree = hIsRegFree( FB_DATACLASS_INTEGER, reg )
	if( isfree = FALSE ) then
		hPUSH( aux )
	end if

	ofs = 0
	'' move dwords
	for i = 1 to cunsg(bytes) \ 4
		hPrepOperand( svreg, src, FB_DATATYPE_INTEGER, ofs )
		hMOV( aux, src )
		hPrepOperand( dvreg, dst, FB_DATATYPE_INTEGER, ofs )
		hMOV( dst, aux )
		ofs += 4
	next

	'' a word left?
	if( (bytes and 2) <> 0 ) then
		aux = *hGetRegName( FB_DATATYPE_SHORT, reg )
		hPrepOperand( svreg, src, FB_DATATYPE_SHORT, ofs )
		hMOV( aux, src )
		hPrepOperand( dvreg, dst, FB_DATATYPE_SHORT, ofs )
		hMOV( dst, aux )
		ofs += 2
	end if

	'' a byte left?
	if( (bytes and 1) <> 0 ) then
		aux = *hGetRegName( FB_DATATYPE_BYTE, reg )
		hPrepOperand( svreg, src, FB_DATATYPE_BYTE, ofs )
		hMOV( aux, src )
		hPrepOperand( dvreg, dst, FB_DATATYPE_BYTE, ofs )
		hMOV( dst, aux )
	end if

	if( isfree = FALSE ) then
		hPOP( aux )
	end if

end sub

'':::::
private sub _emitMEMMOVE _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr, _
		byval bytes as integer, _
		byval extra as integer _
	) static

	if( bytes > 16 ) then
		hMemMoveRep( dvreg, svreg, bytes )
	else
		hMemMoveBlk( dvreg, svreg, bytes )
	end if

end sub

'':::::
private sub _emitMEMSWAP _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr, _
		byval bytes as integer, _
		byval extra as integer _
	) static

	'' implemented as function

end sub

'':::::
private sub hMemClearRep _
	( _
		byval dvreg as IRVREG ptr, _
		byval bytes as integer _
	) static

	dim as string dst
	dim as string ostr
	dim as integer eaxfree, ecxfree, edifree

	hPrepOperand( dvreg, dst, , , , FALSE )

	eaxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_EAX )
	ecxfree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_ECX )
	edifree = hIsRegFree( FB_DATACLASS_INTEGER, EMIT_REG_ESI )

	if( eaxfree = FALSE ) then
		hPUSH( "eax" )
	end if
	if( ecxfree = FALSE ) then
		hPUSH( "ecx" )
	end if
	if( edifree = FALSE ) then
		hPUSH( "edi" )
	end if

	ostr = "lea edi, " + dst
	outp ostr

	outp "xor eax, eax"

	if( bytes > 4 ) then
		ostr = "mov ecx, " + str( cunsg(bytes) \ 4 )
		outp ostr
		outp "rep stosd"

	elseif( bytes = 4 ) then
		outp "mov dword ptr [edi], eax"
		if( (bytes and 3) > 0 ) then
			outp "add edi, 4"
		end if
	end if

	bytes and= 3
	if( bytes > 0 ) then
		if( bytes >= 2 ) then
			outp "mov word ptr [edi], ax"
			if( bytes = 3 ) then
				outp "add edi, 2"
			end if
		end if

		if( (bytes and 1) <> 0 ) then
			outp "mov byte ptr [edi], al"
		end if
	end if

	if( edifree = FALSE ) then
		hPOP( "edi" )
	end if
	if( ecxfree = FALSE ) then
		hPOP( "ecx" )
	end if
	if( eaxfree = FALSE ) then
		hPOP( "eax" )
	end if

end sub

'':::::
private sub hMemClearBlk _
	( _
		byval dvreg as IRVREG ptr, _
		byval bytes as integer _
	) static

	dim as string dst
	dim as integer i, ofs

	ofs = 0
	'' move dwords
	for i = 1 to cunsg(bytes) \ 4
		hPrepOperand( dvreg, dst, FB_DATATYPE_INTEGER, ofs )
		hMOV( dst, "0" )
		ofs += 4
	next

	'' a word left?
	if( (bytes and 2) <> 0 ) then
		hPrepOperand( dvreg, dst, FB_DATATYPE_SHORT, ofs )
		hMOV( dst, "0" )
		ofs += 2
	end if

	'' a byte left?
	if( (bytes and 1) <> 0 ) then
		hPrepOperand( dvreg, dst, FB_DATATYPE_BYTE, ofs )
		hMOV( dst, "0" )
	end if

end sub

'':::::
private sub _emitMEMCLEAR _
	( _
		byval dvreg as IRVREG ptr, _
		byval unused as IRVREG ptr, _
		byval bytes as integer, _
		byval extra as integer _
	) static

	if( bytes > 16 ) then
		hMemClearRep( dvreg, bytes )
	else
		hMemClearBlk( dvreg, bytes )
	end if

end sub

declare sub hClearLocals( byval bytestoclear as integer, byval baseoffset as integer )

'':::::
private sub _emitSTKCLEAR _
	( _
		byval dvreg as IRVREG ptr, _
		byval svreg as IRVREG ptr, _
		byval bytes as integer, _
		byval baseofs as integer _
	) static

	hClearLocals( bytes, baseofs )

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' procs
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

private sub hClearLocals _
	( _
		byval bytestoclear as integer, _
		byval baseoffset as integer _
	) static

	dim as integer i
    dim as string lname

	if( bytestoclear = 0 ) then
		exit sub
	end if

	if( env.clopt.cputype >= FB_CPUTYPE_686 ) then
		if( cunsg(bytestoclear) \ 8 > 7 ) then

	    	if( EMIT_REGISUSED( FB_DATACLASS_INTEGER, EMIT_REG_EDI ) = FALSE ) then
    			hPUSH( "edi" )
    		end if

			outp( "lea edi, [ebp-" & baseoffset + bytestoclear & "]" )
			outp( "mov ecx," & cunsg(bytestoclear) \ 8 )
			outp( "pxor mm0, mm0" )
		    lname = *hMakeTmpStr( )
		    hLABEL( lname )
			outp( "movq [edi], mm0" )
			outp( "add edi, 8" )
			outp( "dec ecx" )
			outp( "jnz " + lname )
			outp( "emms" )

    		if( EMIT_REGISUSED( FB_DATACLASS_INTEGER, EMIT_REG_EDI ) = FALSE ) then
    			hPOP( "edi" )
    		end if

		elseif( cunsg(bytestoclear) \ 8 > 0 ) then
			outp( "pxor mm0, mm0" )
			for i = cunsg(bytestoclear) \ 8 to 1 step -1
				outp( "movq [ebp-" & ( i*8 ) & "], mm0" )
			next
			outp( "emms" )

		end if

		if( bytestoclear and 4 ) then
			outp( "mov dword ptr [ebp-" & baseoffset + bytestoclear & "], 0" )
		end if

		exit sub
	end if

	if( cunsg(bytestoclear) \ 4 > 6 ) then

    	if( EMIT_REGISUSED( FB_DATACLASS_INTEGER, EMIT_REG_EDI ) = FALSE ) then
   			hPUSH( "edi" )
   		end if

		outp( "lea edi, [ebp-" & baseoffset + bytestoclear & "]" )
		outp( "mov ecx," & cunsg(bytestoclear) \ 4 )
		outp( "xor eax, eax" )
		outp( "rep stosd" )

   		if( EMIT_REGISUSED( FB_DATACLASS_INTEGER, EMIT_REG_EDI ) = FALSE ) then
   			hPOP( "edi" )
   		end if

	else
		for i = cunsg(bytestoclear) \ 4 to 1 step -1
			 outp( "mov dword ptr [ebp-" & baseoffset + ( i*4 ) & "], 0" )
		next
	end if

end sub

'':::::
private sub hCreateFrame _
	( _
		byval proc as FBSYMBOL ptr _
	) static

    dim as integer bytestoalloc, bytestoclear

    bytestoalloc = ((proc->proc.ext->stk.localmax - EMIT_LOCSTART) + 3) and (not 3)

    if( (bytestoalloc <> 0) or _
    	(proc->proc.ext->stk.argofs <> EMIT_ARGSTART) or _
        symbGetIsMainProc( proc ) or _
        env.clopt.debug ) then

    	hPUSH( "ebp" )
    	outp( "mov ebp, esp" )

        if( symbGetIsMainProc( proc ) ) then
			outp( "and esp, 0xFFFFFFF0" )
	    end if

    	if( bytestoalloc > 0 ) then
    		outp( "sub esp, " + str( bytestoalloc ) )
    	end if
    end if

    if( EMIT_REGISUSED( FB_DATACLASS_INTEGER, EMIT_REG_EBX ) ) then
    	hPUSH( "ebx" )
    end if
    if( EMIT_REGISUSED( FB_DATACLASS_INTEGER, EMIT_REG_ESI ) ) then
    	hPUSH( "esi" )
    end if
    if( EMIT_REGISUSED( FB_DATACLASS_INTEGER, EMIT_REG_EDI ) ) then
    	hPUSH( "edi" )
    end if

	''
#if 0
	bytestoclear = ((proc->proc.ext->stk.localofs - EMIT_LOCSTART) + 3) and (not 3)

	hClearLocals( bytestoclear, 0 )
#endif

end sub

''::::
private sub hDestroyFrame _
	( _
		byval proc as FBSYMBOL ptr, _
		byval bytestopop as integer _
	) static

    dim as integer bytestoalloc

    bytestoalloc = ((proc->proc.ext->stk.localmax - EMIT_LOCSTART) + 3) and (not 3)

    if( EMIT_REGISUSED( FB_DATACLASS_INTEGER, EMIT_REG_EDI ) ) then
    	hPOP( "edi" )
    end if
    if( EMIT_REGISUSED( FB_DATACLASS_INTEGER, EMIT_REG_ESI ) ) then
    	hPOP( "esi" )
    end if
    if( EMIT_REGISUSED( FB_DATACLASS_INTEGER, EMIT_REG_EBX ) ) then
    	hPOP( "ebx" )
    end if

    if( (bytestoalloc <> 0) or _
    	(proc->proc.ext->stk.argofs <> EMIT_ARGSTART) or _
        symbGetIsMainProc( proc ) or _
        env.clopt.debug ) then
    	outp( "mov esp, ebp" )
    	hPOP( "ebp" )
    end if

    if( bytestopop > 0 ) then
    	outp( "ret " + str( bytestopop ) )
    else
    	outp( "ret" )
    end if

	if( env.clopt.target = FB_COMPTARGET_LINUX ) then
    	outEx( ".size " + *symbGetMangledName( proc ) + ", .-" + *symbGetMangledName( proc ) + NEWLINE )
	end if

end sub

'':::::
sub emitPROCHEADER _
	( _
		byval proc as FBSYMBOL ptr, _
		byval initlabel as FBSYMBOL ptr _
	) static

	'' do nothing, proc will be only emitted at PROCFOOTER

	emitReset( )

	edbgProcEmitBegin( proc )

end sub

'':::::
sub emitPROCFOOTER _
	( _
		byval proc as FBSYMBOL ptr, _
		byval bytestopop as integer, _
		byval initlabel as FBSYMBOL ptr, _
		byval exitlabel as FBSYMBOL ptr _
	) static

    dim as integer oldpos, ispublic

    ispublic = symbIsPublic( proc )

	emitSECTION( EMIT_SECTYPE_CODE )

	''
	edbgEmitProcHeader( proc )

	''
	hALIGN( 16 )

	if( ispublic ) then
		hPUBLIC( symbGetMangledName( proc ) )
	end if

	hLABEL( symbGetMangledName( proc ) )

	if( env.clopt.target = FB_COMPTARGET_LINUX ) then
		outEx( ".type " + *symbGetMangledName( proc ) + ", @function" + NEWLINE )
	end if

	'' frame
	hCreateFrame( proc )

    edbgEmitLineFlush( proc, proc->proc.ext->dbg.iniline, proc )

    ''
    emitFlush( )

	''
	hDestroyFrame( proc, bytestopop )

    edbgEmitLineFlush( proc, proc->proc.ext->dbg.endline, exitlabel )

    edbgEmitProcFooter( proc, initlabel, exitlabel )

end sub

'':::::
function emitAllocLocal _
	( _
		byval proc as FBSYMBOL ptr, _
		byval lgt as integer _
	) as integer static

    dim as integer ofs

    proc->proc.ext->stk.localofs += ((lgt + 3) and not 3)

	ofs = -proc->proc.ext->stk.localofs

    if( -ofs > proc->proc.ext->stk.localmax ) then
    	proc->proc.ext->stk.localmax = -ofs
    end if

	function = ofs

end function

'':::::
function emitAllocArg _
	( _
		byval proc as FBSYMBOL ptr, _
		byval lgt as integer _
	) as integer static

	function = proc->proc.ext->stk.argofs

    proc->proc.ext->stk.argofs += ((lgt + 3) and not 3)

end function

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' global ctors
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
sub emitWriteCtorSection _
	( _
		byval proc_head as FB_GLOBCTORLIST_ITEM ptr, _
		byval is_ctor as integer _
	)

    if( proc_head = NULL ) then
    	exit sub
    end if

    do
    	'' was it emitted?
    	if( symbGetProcIsEmitted( proc_head->sym ) ) then
    		emitSECTION( iif( is_ctor, EMIT_SECTYPE_CONSTRUCTOR, EMIT_SECTYPE_DESTRUCTOR ) )
    		emitVARINIOFS( symbGetMangledName( proc_head->sym ), 0 )
    	end if

    	proc_head = proc_head->next
    loop while( proc_head <> NULL )

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' data
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
sub emitDATALABEL _
	( _
		byval label as zstring ptr _
	) static

    dim ostr as string

	ostr = *label
	ostr += ":" + NEWLINE
	outEx( ostr )

end sub

'':::::
sub emitDATABEGIN _
	( _
		byval lname as zstring ptr _
	) static

    dim as string ostr
    dim as integer currpos

	if( emit.dataend <> 0 ) then
		currpos = seek( env.outf.num )

		seek #env.outf.num, emit.dataend

		ostr = ".int "
		ostr += *lname
		ostr += NEWLINE
		outEx( ostr )

		seek #env.outf.num, currpos

    end if

end sub

'':::::
sub emitDATAEND static
    dim as string ostr

    '' link + NULL
    outEx( ".short 0xffff" + NEWLINE )

    emit.dataend = seek( env.outf.num )

    ostr = ".int 0" + space( FB_MAXNAMELEN ) + NEWLINE
    outEx( ostr )

end sub

'':::::
sub emitDATA _
	( _
		byval litext as zstring ptr, _
		byval litlen as integer, _
		byval typ as integer _
	) static

    static as zstring ptr esctext
    dim as string ostr

    esctext = hEscape( litext )

	'' len + asciiz
	if( typ <> INVALID ) then
		ostr = ".short 0x" + hex( litlen ) + NEWLINE
		outEx( ostr )

		ostr = ".ascii " + QUOTE
		ostr += *esctext
		ostr += RSLASH + "0" + QUOTE + NEWLINE
		outEx( ostr )
	else
		outEx( ".short 0x0000" + NEWLINE )
	end if

end sub

'':::::
sub emitDATAW _
	( _
		byval litext as wstring ptr, _
		byval litlen as integer, _
		byval typ as integer _
	) static

    static as zstring ptr esctext
    dim as string ostr

    esctext = hEscapeW( litext )

	'' (0x8000 or len) + unicode
	if( typ <> INVALID ) then
		ostr = ".short 0x" + hex( &h8000 or litlen ) + NEWLINE
		outEx( ostr )

		ostr = ".ascii " + QUOTE + *esctext + *hGetWstrNull( ) + (QUOTE + NEWLINE)
		outEx( ostr )
	else
		outEx( ".short 0x0000" + NEWLINE )
	end if

end sub

'':::::
sub emitDATAOFS _
	( _
		byval sname as zstring ptr _
	) static

    dim ostr as string

	outEx( ".short 0xfffe" + NEWLINE )

	ostr = ".int "
	ostr += *sname
	ostr += NEWLINE
	outEx( ostr )

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' initializers
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
sub emitVARINIBEGIN _
	( _
		byval sym as FBSYMBOL ptr _
	) static

	emitSECTION( EMIT_SECTYPE_DATA )

	'' add dbg info, if public or shared
    'if( (symbGetAttrib( sym ) and (FB_SYMBATTRIB_SHARED or FB_SYMBATTRIB_PUBLIC)) > 0 ) then
   		edbgEmitGlobalVar( sym, EMIT_SECTYPE_DATA )
   	'end if

   	if( symbGetType( sym ) = FB_DATATYPE_DOUBLE ) then
    	hALIGN( 8 )
	else
    	hALIGN( 4 )
	end if

	'' public?
	if( symbIsPublic( sym ) ) then
		hPUBLIC( *symbGetMangledName( sym ) )
	end if

	hLABEL( *symbGetMangledName( sym ) )

end sub

'':::::
sub emitVARINIEND _
	( _
		byval sym as FBSYMBOL ptr _
	) static

end sub

'':::::
sub emitVARINIi _
	( _
		byval dtype as integer, _
		byval value as integer _
	) static

	dim ostr as string

	ostr = hGetTypeString( dtype ) + " " + str( value ) + NEWLINE
	outEx( ostr )

end sub

'':::::
sub emitVARINIf _
	( _
		byval dtype as integer, _
		byval value as double _
	) static

	dim as string svalue, ostr

	'' can't use STR() because GAS doesn't support the 1.#INF notation
	svalue = hFloatToStr( value, dtype )

	ostr = hGetTypeString( dtype ) + " " + svalue + NEWLINE
	outEx( ostr )

end sub

'':::::
sub emitVARINI64 _
	( _
		byval dtype as integer, _
		byval value as longint _
	) static

	dim ostr as string

	ostr = hGetTypeString( dtype ) + " 0x" + hex( value ) + NEWLINE
	outEx( ostr )

end sub

'':::::
sub emitVARINIOFS _
	( _
		byval sname as zstring ptr, _
		byval ofs as integer _
	) static

	dim as string ostr

	ostr = ".int "
	ostr += *sname
	if( ofs <> 0 ) then
		ostr += " + "
		ostr += str( ofs )
	end if
	ostr += NEWLINE
	outEx( ostr )

end sub

'':::::
sub emitVARINISTR _
	( _
		byval s as zstring ptr _
	) static

    dim ostr as string

	ostr = ".ascii " + QUOTE
	ostr += *s
	ostr += RSLASH + "0" + QUOTE + NEWLINE
	outEx( ostr )

end sub

'':::::
sub emitVARINIWSTR _
	( _
		byval s as zstring ptr _
	) static

    dim ostr as string

	ostr = ".ascii " + QUOTE
	ostr += *s
	ostr += *hGetWstrNull( )
	ostr += QUOTE + NEWLINE
	outEx( ostr )

end sub

'':::::
sub emitVARINIPAD _
	( _
		byval bytes as integer _
	) static

    dim ostr as string

	ostr = ".skip " + str( bytes ) + ",0" + NEWLINE
	outEx( ostr )

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' high-level
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
#define hEmitBssHeader( ) emitSECTION( EMIT_SECTYPE_BSS )

'':::::
#define hEmitConstHeader( ) emitSECTION( EMIT_SECTYPE_DATA )

'':::::
#define hEmitDataHeader( ) emitSECTION( EMIT_SECTYPE_DATA )

'':::::
#define hEmitExportHeader( ) emitSECTION( EMIT_SECTYPE_DIRECTIVE )

'':::::
sub emitWriteHeader( ) static

	''
	edbgEmitHeader( env.inf.name )

	''
	hWriteStr( TRUE,  ".intel_syntax noprefix" )
    hWriteStr( FALSE, "" )
    hCOMMENT( env.inf.name + "' compilation started at " + time + " (" + FB_SIGN + ")" )

end sub

'':::::
sub emitWriteFooter _
	( _
		byval tottime as double _
	) static

	hCOMMENT( env.inf.name + "' compilation took " + str( tottime ) + " secs" )

	''
	edbgIncludeEnd( )

end sub

'':::::
private function hGetTypeString _
	( _
		byval typ as integer _
	) as string static

	select case as const typ
    case FB_DATATYPE_UBYTE, FB_DATATYPE_BYTE
    	function = ".byte"

    case FB_DATATYPE_USHORT, FB_DATATYPE_SHORT
    	function = ".short"

    case FB_DATATYPE_INTEGER, FB_DATATYPE_UINT, FB_DATATYPE_ENUM
    	function = ".int"

    case FB_DATATYPE_LONGINT, FB_DATATYPE_ULONGINT
    	function = ".quad"

    case FB_DATATYPE_SINGLE
		function = ".float"

	case FB_DATATYPE_DOUBLE
    	function = ".double"

	case FB_DATATYPE_FIXSTR, FB_DATATYPE_CHAR, FB_DATATYPE_WCHAR
		'' wchar stills the same as it is emitted as escape sequences
    	function = ".ascii"

    case FB_DATATYPE_STRING
    	function = ".int"

	case FB_DATATYPE_STRUCT
		function = "INVALID"

    case else
    	if( typ >= FB_DATATYPE_POINTER ) then
    		function = ".int"
    	end if
	end select

end function

'':::::
private sub hEmitVarBss _
	( _
		byval s as FBSYMBOL ptr _
	) static

    dim as string alloc, ostr
    dim as integer attrib, elements

	attrib = symbGetAttrib( s )

	elements = 1
    if( symbGetArrayDimensions( s ) > 0 ) then
    	elements = symbGetArrayElements( s )
	end if

    hEmitBssHeader( )

    '' allocation modifier
    if( (attrib and FB_SYMBATTRIB_COMMON) = 0 ) then
      	if( (attrib and FB_SYMBATTRIB_PUBLIC) > 0 ) then
       		hPUBLIC( *symbGetMangledName( s ) )
		end if
       	alloc = ".lcomm"
	else
       	hPUBLIC( *symbGetMangledName( s ) )
       	alloc = ".comm"
    end if

    '' align
    if( symbGetType( s ) = FB_DATATYPE_DOUBLE ) then
    	hALIGN( 8 )
    	hWriteStr( TRUE, ".balign 8" )
	else
    	hALIGN( 4 )
    end if

	'' emit
    ostr = alloc + TABCHAR
    ostr += *symbGetMangledName( s )
    ostr += "," + str( symbGetLen( s ) * elements )
    hWriteStr( TRUE, ostr )

    '' add dbg info, if public or shared
    if( (attrib and (FB_SYMBATTRIB_SHARED or _
    				 FB_SYMBATTRIB_COMMON or _
    				 FB_SYMBATTRIB_PUBLIC)) > 0 ) then
    	edbgEmitGlobalVar( s, EMIT_SECTYPE_BSS )
	end if

end sub

'':::::
sub emitWriteBss _
	( _
		byval s as FBSYMBOL ptr )

    do while( s <> NULL )

    	select case symbGetClass( s )
		'' name space?
		case FB_SYMBCLASS_NAMESPACE
			emitWriteBss( symbGetNamespaceTbHead( s ) )

		'' scope block?
		case FB_SYMBCLASS_SCOPE
			emitWriteBss( symbGetScopeSymbTbHead( s ) )

    	'' variable?
    	case FB_SYMBCLASS_VAR
    		emitDeclVariable( s )

    	end select

    	s = s->next
    loop

end sub

'':::::
private sub hEmitVarConst _
	( _
		byval s as FBSYMBOL ptr _
	) static

    dim as string stext, stype, ostr
    dim as integer dtype

    dtype = symbGetType( s )

    select case dtype
   	case FB_DATATYPE_CHAR
    	stext = QUOTE
    	stext += *hEscape( symbGetVarLitText( s ) )
    	stext += RSLASH + "0" + QUOTE

	case FB_DATATYPE_WCHAR
		stext = QUOTE
		stext += *hEscapeW( symbGetVarLitTextW( s ) )
		stext += *hGetWstrNull( )
		stext += QUOTE

	case else
    	stext = *symbGetVarLitText( s )
    end select

    hEmitConstHeader( )

    if( dtype = FB_DATATYPE_DOUBLE ) then
       	hALIGN( 8 )
    else
      	hALIGN( 4 )
    end if

    stype = hGetTypeString( dtype )
    ostr = *symbGetMangledName( s )
    ostr += (":" + TABCHAR) + stype + TABCHAR + stext
    hWriteStr( FALSE, ostr )

end sub

'':::::
sub emitWriteConst _
	( _
		byval s as FBSYMBOL ptr )

    do while( s <> NULL )

    	select case symbGetClass( s )
		'' name space?
		case FB_SYMBCLASS_NAMESPACE
			emitWriteConst( symbGetNamespaceTbHead( s ) )

		'' scope block?
		case FB_SYMBCLASS_SCOPE
			emitWriteConst( symbGetScopeSymbTbHead( s ) )

    	'' variable?
    	case FB_SYMBCLASS_VAR
    		emitDeclVariable( s )
		end select

    	s = s->next
    loop

end sub

'':::::
sub emitWriteData _
	( _
		byval s as FBSYMBOL ptr )

    do while( s <> NULL )

    	select case symbGetClass( s )
		'' name space?
		case FB_SYMBCLASS_NAMESPACE
			emitWriteData( symbGetNamespaceTbHead( s ) )

		'' scope block?
		case FB_SYMBCLASS_SCOPE
			emitWriteData( symbGetScopeSymbTbHead( s ) )

    	'' variable?
    	case FB_SYMBCLASS_VAR
    		emitDeclVariable( s )

    	end select

    	s = s->next
    loop

end sub

'':::::
sub emitWriteExport _
	(  _
		byval s as FBSYMBOL ptr _
	) static

    dim as string sname

    '' for each proc exported..
    do while( s <> NULL )
    	select case symbGetClass( s )
		'' name space?
		case FB_SYMBCLASS_NAMESPACE
			emitWriteExport( symbGetNamespaceTbHead( s ) )

    	case FB_SYMBCLASS_PROC
    		if( symbGetIsDeclared( s ) ) then
    			if( symbIsExport( s ) ) then
    				hEmitExportHeader( )
    				sname = hStripUnderscore( symbGetMangledName( s ) )
    				hWriteStr( TRUE, ".ascii " + QUOTE + " -export:" + sname + (QUOTE + NEWLINE) )
    			end if
    		end if
    	end select

    	s = s->next
    loop

end sub

'':::::
sub emitDeclVariable _
	( _
		byval s as FBSYMBOL ptr _
	) static

    '' already allocated?
	if( symbGetVarIsAllocated( s ) ) then
		return
	end if

	symbSetVarIsAllocated( s )

	'' literal?
    if( symbGetIsLiteral( s ) ) then

    	select case symbGetType( s )
    	'' udt? don't emit
    	case FB_DATATYPE_STRUCT
    		return

    	'' string? check if ever referenced
    	case FB_DATATYPE_CHAR, FB_DATATYPE_WCHAR
    	  	if( symbGetIsAccessed( s ) = FALSE ) then
    	  		return
    	  	end if

		'' anything else, only if len > 0
		case else
			if( symbGetLen( s ) <= 0 ) then
				return
			end if
    	end select

    	hEmitVarConst( s )

    	return
	end if

	'' initialized?
	if( symbGetIsInitialized( s ) ) then

		'' extern or jump-tb?
    	if( symbIsExtern( s ) ) then
			return
		elseif( symbGetIsJumpTb( s ) ) then
			return
		end if

    	'' never referenced?
    	if( symbGetIsAccessed( s ) = FALSE ) then
			'' not public?
    	    if( symbIsPublic( s ) = FALSE ) then
    	    	return
    	    end if
		end if

		hEmitDataHeader( )
		astTypeIniFlush( s->var.initree, s, TRUE, TRUE )

		return
	end if

    '' extern or dynamic (for the latter, only the array descriptor is emitted)?
	if( (s->attrib and (FB_SYMBATTRIB_EXTERN or _
			   			FB_SYMBATTRIB_DYNAMIC)) <> 0 ) then
		return
	end if

    '' a string or array descriptor?
	if( symbGetLen( s ) <= 0 ) then
		return
	end if

	hEmitVarBss( s )

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' functions table
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

#define EMIT_CBENTRY(op) @_emit##op##

	'' same order as EMIT_NODEOP_ENUM
	dim shared emit_opfTB(0 to EMIT_MAXOPS-1) as any ptr => _
	{ _
		EMIT_CBENTRY(LOADI2I), EMIT_CBENTRY(LOADF2I), EMIT_CBENTRY(LOADL2I), _
		EMIT_CBENTRY(LOADI2F), EMIT_CBENTRY(LOADF2F), EMIT_CBENTRY(LOADL2F), _
		EMIT_CBENTRY(LOADI2L), EMIT_CBENTRY(LOADF2L), EMIT_CBENTRY(LOADL2L), _
        _
		EMIT_CBENTRY(STORI2I), EMIT_CBENTRY(STORF2I), EMIT_CBENTRY(STORL2I), _
		EMIT_CBENTRY(STORI2F), EMIT_CBENTRY(STORF2F), EMIT_CBENTRY(STORL2F), _
		EMIT_CBENTRY(STORI2L), EMIT_CBENTRY(STORF2L), EMIT_CBENTRY(STORL2L), _
        _
		EMIT_CBENTRY(MOVI), EMIT_CBENTRY(MOVF), EMIT_CBENTRY(MOVL), _
		EMIT_CBENTRY(ADDI), EMIT_CBENTRY(ADDF), EMIT_CBENTRY(ADDL), _
		EMIT_CBENTRY(SUBI), EMIT_CBENTRY(SUBF), EMIT_CBENTRY(SUBL), _
		EMIT_CBENTRY(MULI), EMIT_CBENTRY(MULF), EMIT_CBENTRY(MULL), EMIT_CBENTRY(SMULI), _
		EMIT_CBENTRY(DIVI), EMIT_CBENTRY(DIVF), NULL              , _
		EMIT_CBENTRY(MODI), NULL              , NULL              , _
		EMIT_CBENTRY(SHLI), EMIT_CBENTRY(SHLL), _
		EMIT_CBENTRY(SHRI), EMIT_CBENTRY(SHRL), _
		EMIT_CBENTRY(ANDI), EMIT_CBENTRY(ANDL), _
		EMIT_CBENTRY(ORI) , EMIT_CBENTRY(ORL) , _
		EMIT_CBENTRY(XORI), EMIT_CBENTRY(XORL), _
		EMIT_CBENTRY(EQVI), EMIT_CBENTRY(EQVL), _
		EMIT_CBENTRY(IMPI), EMIT_CBENTRY(IMPL), _
		EMIT_CBENTRY(ATN2), _
		EMIT_CBENTRY(POW), _
		EMIT_CBENTRY(ADDROF), _
		EMIT_CBENTRY(DEREF), _
        _
		EMIT_CBENTRY(CGTI), EMIT_CBENTRY(CGTF), EMIT_CBENTRY(CGTL), _
		EMIT_CBENTRY(CLTI), EMIT_CBENTRY(CLTF), EMIT_CBENTRY(CLTL), _
		EMIT_CBENTRY(CEQI), EMIT_CBENTRY(CEQF), EMIT_CBENTRY(CEQL), _
		EMIT_CBENTRY(CNEI), EMIT_CBENTRY(CNEF), EMIT_CBENTRY(CNEL), _
		EMIT_CBENTRY(CGEI), EMIT_CBENTRY(CGEF), EMIT_CBENTRY(CGEL), _
		EMIT_CBENTRY(CLEI), EMIT_CBENTRY(CLEF), EMIT_CBENTRY(CLEL), _
        _
		EMIT_CBENTRY(NEGI), EMIT_CBENTRY(NEGF), EMIT_CBENTRY(NEGL), _
		EMIT_CBENTRY(NOTI), EMIT_CBENTRY(NOTL), _
		EMIT_CBENTRY(ABSI), EMIT_CBENTRY(ABSF), EMIT_CBENTRY(ABSL), _
		EMIT_CBENTRY(SGNI), EMIT_CBENTRY(SGNF), EMIT_CBENTRY(SGNL), _
        _
		EMIT_CBENTRY(SIN), EMIT_CBENTRY(ASIN), _
		EMIT_CBENTRY(COS), EMIT_CBENTRY(ACOS), _
		EMIT_CBENTRY(TAN), EMIT_CBENTRY(ATAN), _
		EMIT_CBENTRY(SQRT), _
		EMIT_CBENTRY(LOG), _
		EMIT_CBENTRY(FLOOR), _
		EMIT_CBENTRY(XCHGTOS), _
        _
		EMIT_CBENTRY(ALIGN), _
		EMIT_CBENTRY(STKALIGN), _
        _
		EMIT_CBENTRY(PUSHI), EMIT_CBENTRY(PUSHF), EMIT_CBENTRY(PUSHL), _
		EMIT_CBENTRY(POPI), EMIT_CBENTRY(POPF), EMIT_CBENTRY(POPL), _
		EMIT_CBENTRY(PUSHUDT), _
        _
		EMIT_CBENTRY(CALL), _
		EMIT_CBENTRY(CALLPTR), _
		EMIT_CBENTRY(BRANCH), _
		EMIT_CBENTRY(JUMP), _
		EMIT_CBENTRY(JUMPPTR), _
		EMIT_CBENTRY(RET), _
        _
		EMIT_CBENTRY(LABEL), _
		EMIT_CBENTRY(PUBLIC), _
		EMIT_CBENTRY(LIT), _
		EMIT_CBENTRY(JMPTB), _
        _
		EMIT_CBENTRY(MEMMOVE), _
		EMIT_CBENTRY(MEMSWAP), _
		EMIT_CBENTRY(MEMCLEAR), _
		EMIT_CBENTRY(STKCLEAR) _
	}

