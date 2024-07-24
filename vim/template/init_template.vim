
call plug#begin('___VIM_BASE_DIR___/plugin')

	Plug 'SirVer/ultisnips'
	Plug 'honza/vim-snippets'

	" Commenter which works with visualmode etc.
	Plug 'scrooloose/nerdcommenter'
	Plug 'scrooloose/nerdtree', { 'do': ':NERDTreeToggle' }

	" Better vim tabs
	Plug 'jistr/vim-nerdtree-tabs'

	" Themes for status line
	Plug 'vim-airline/vim-airline'
	Plug 'vim-airline/vim-airline-themes'

	" Better icons :)
	Plug 'ryanoasis/vim-devicons'

	Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
	"Plug 'Shougo/neoinclude.vim'

	" Fuzy file finder
	Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
	Plug 'junegunn/fzf.vim'

call plug#end()

" Close all open buffers on entering a window if the only
" buffer that's left is the NERDTree buffer
function! s:CloseIfOnlyNerdTreeLeft()
  if exists("t:NERDTreeBufName")
    if bufwinnr(t:NERDTreeBufName) != -1
      if winnr("$") == 1
        q
      endif
    endif
  endif
endfunction

autocmd WinEnter * call s:CloseIfOnlyNerdTreeLeft()



let g:deoplete#enable_at_startup = 1

let g:nerdtree_tabs_autoclose = 1
let g:nerdtree_tabs_open_on_console_startup = 1

let g:airline_theme = 'dark'
let g:airline_powerline_fonts = 1

let g:UltiSnipsExpandTrigger="<c-a>"

let g:fzf_action = {
  \ 'ctrl-t': 'tab split',
  \ 'ctrl-x': 'split',
  \ 'ctrl-v': 'vsplit' }

set background=dark
set shiftwidth=4
set tabstop=4

set fileformats=unix,dos
set fileencodings=UTF-8,latin1
set encoding=UTF-8

set number
set nowrap
set autowrite

" set mouse in all modes
set mouse=a