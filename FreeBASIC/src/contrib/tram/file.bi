#ifndef __fb_file_bi__
#define __fb_file_bi__

#ifndef FALSE
# define FALSE 0
# define TRUE -1
#endif

#define NULL 0

namespace fb.file

	type CSearchEntry
		path	as zstring ptr
		name	as zstring ptr
		serial	as double
	end type

	type CSearchDirCallback as function _
		( _
			byval path as zstring ptr, _
			byval fname as zstring ptr _
		) as integer
		
	type CSearchCtx as CSearchCtx_

	type CSearch
		enum searchBy
			searchBy_SerialNewer
			searchBy_SerialOlder
			searchBy_SerialSame
		end enum
		
		declare constructor _
			( _
				byval root as zstring ptr, _
				byval dirCb as CSearchDirCallback = NULL _
			) 
	
		declare destructor _
			( _
			) 
	
		declare function byDate _
			( _
				byval mask as zstring ptr, _
				byval serial as double, _
				byval mode as searchBy = searchBy_SerialNewer _
			) as integer
	
		declare function getFirst _
			( _
			) as CSearchEntry ptr
			
		declare function getNext _
			( _
			) as CSearchEntry ptr
	
		ctx as CSearchCtx ptr
	end type

end namespace

#endif '' __fb_file_bi__