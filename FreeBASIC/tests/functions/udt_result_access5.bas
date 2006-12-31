# include "fbcu.bi"

namespace fbc_tests.functions.udt_result_access5

dim shared as integer dtor_cnt = 0

type tbar
	declare destructor
	int1 as integer = 1234
	int2 as integer = -1234
end type

destructor tbar
	dtor_cnt += 1
end destructor

type tfoo
	declare constructor ( )
	declare constructor ( byref as tbar ) 
	declare function bar ( ) as tbar
private:	
	p_bar as tbar
end type

constructor tfoo ( )
	
end constructor

constructor tfoo ( byref rhs as tbar )
	p_bar = rhs
end constructor

function tfoo.bar ( ) as tbar
	return p_bar
end function

	dim shared as tfoo g_f1
	dim shared as tfoo g_f2 = ( g_f1.bar() )

sub test_1 cdecl
	CU_ASSERT_EQUAL( dtor_cnt, 1 )
end sub

sub ctor () constructor

	fbcu.add_suite("fbc_tests.functions.udt_result_access5")
	fbcu.add_test("#1", @test_1)

end sub

end namespace
