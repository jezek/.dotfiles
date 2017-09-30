" vim-plug config
call plug#begin()
Plug 'altercation/vim-colors-solarized'
Plug 'vim-airline/vim-airline' | Plug 'vim-airline/vim-airline-themes'
Plug 'fatih/vim-go'
" Plug 'ctrlpvim/ctrlp.vim'
Plug 'Yggdroot/LeaderF'
Plug 'majutsushi/tagbar'
Plug 'AndrewRadev/splitjoin.vim'
Plug 'Shougo/neocomplete'
Plug 'Shougo/neosnippet' | Plug 'Shougo/neosnippet-snippets'
Plug 'chrisbra/csv.vim'
Plug 'tpope/vim-fugitive'
Plug 'vim-syntastic/syntastic'
call plug#end()

""""""""""""""""""""""
"      Settings      "
""""""""""""""""""""""
set nocompatible                " Enables us Vim specific features
filetype off                    " Reset filetype detection first ...
filetype plugin indent on       " ... and enable filetype detection
set ttyfast                     " Indicate fast terminal conn for faster redraw
set ttymouse=xterm2             " Indicate terminal type for mouse codes
set ttyscroll=3                 " Speedup scrolling
set laststatus=2                " Show status line always
set encoding=utf-8              " Set default encoding to UTF-8
set fileencodings=ucs-bom,utf-8,windows-1250,default,latin1
set autoread                    " Automatically read changed files
set autoindent                  " Enabile Autoindent
set smartindent
" a tab is 2 spaces
set tabstop=2
set smarttab
" num of spaces using for autoindent
set shiftwidth=2
"Round indent to multiple of 'shiftwidth'.  Applies to > and < commands
set shiftround
" allow backspacing over everything in insert mode
set backspace=indent,eol,start
set incsearch                   " Shows the match while typing
set hlsearch                    " Highlight found searches
set noerrorbells                " No beeps
set number                      " Show line numbers
set showcmd                     " Show me what I'm typing
set noswapfile                  " Don't use swapfile
set nobackup                    " Don't create annoying backup files
set splitright                  " Vertical windows should be split to right
set splitbelow                  " Horizontal windows should split to bottom
set autowrite                   " Automatically save before :next, :make etc.
set hidden                      " Buffer should still exist if window is closed
set fileformats=unix,dos,mac    " Prefer Unix over Windows over OS 9 formats
set noshowmode                  " We show the mode with airline or lightline
"set noshowmatch                 " Do not show matching brackets by flickering
set ignorecase                  " Search case insensitive...
set smartcase                   " ... but not it begins with upper case
set completeopt=menu,menuone    " Show popup menu, even if there is one entry
set pumheight=10                " Completion window max size
set nocursorcolumn              " Do not highlight column (speeds up highlighting)
set nocursorline                " Do not highlight cursor (speeds up highlighting)
set lazyredraw                  " Wait to redraw
" <Tab> autocompletion like in bash
set wildmode=longest:full       " Complete till longest common string.  If this doesn't result in a longer string, use the next part. Also start 'wildmenu' if it is enabled.
set wildmenu                     " Command-line completion operates in an enhanced mode.
set ruler                        "Always show current posit1ion
" Set 5 lines to the curors - when moving vertical..
set so=5
" do not wrap lines
set nowrap
" mark breaks
let &showbreak = '↳ '
" todo dynamic set cpo=n
" do not resize other splits after new split is created
set noequalalways
" do not show toolbar in gvim
set go-=T

" Enable to copy to clipboard for operations like yank, delete, change and put
" http://stackoverflow.com/questions/20186975/vim-mac-how-to-copy-to-clipboard-without-pbcopy
if has('unnamedplus')
  set clipboard^=unnamed
  set clipboard^=unnamedplus
endif

" This enables us to undo files even if you exit Vim.
if has('persistent_undo')
	let undoDir=expand('~/.vim/undo/')
	call system('mkdir -p ' . undoDir)
  set undofile
  set undodir=~/.vim/undo/
endif

" ------------------------------------------------------------------
" Solarized Colorscheme Config
" ------------------------------------------------------------------
syntax enable
set background=dark
colorscheme solarized
let g:solarized_termcolors=256
set t_Co=16
" let g:solarized_contrast="high"
" ------------------------------------------------------------------

""""""""""""""""""""""
"      Mappings      "
""""""""""""""""""""""

" Set leader shortcut to a comma ','. By default it's the backslash
let mapleader = ","

" Jump to next error with Ctrl-n and previous error with Ctrl-p. Close the
" quickfix window with <leader>a
map <C-n> :cnext<CR>
map <C-m> :cprevious<CR>
nnoremap <leader>a :cclose<CR>

" Visual linewise up and down by default (and use gj gk to go quicker)
noremap <Up> gk
noremap <Down> gj
noremap j gj
noremap k gk

" Search mappings: These will make it so that going to the next one in a
" search will center on the line it's found in.
nnoremap n nzzzv
nnoremap N Nzzzv

" Act like D and C
nnoremap Y y$

" Enter automatically into the files directory
"autocmd BufEnter * silent! lcd %:p:h

" Smart way to move btw. windows
map <C-j> <C-W>j
map <C-k> <C-W>k
map <C-h> <C-W>h
map <C-l> <C-W>l

" map <F2> to toggle paste mode on/off
set pastetoggle=<F2>

" map F4 to select previously pasted text
nnoremap <F4> `[v`]
vnoremap <F4> `[o`]

" Force saving files that require root permission
cmap w!! w !sudo tee > /dev/null %

" Ctrl-s saves
nmap <C-s> <Esc>:w<CR>
imap <C-s> <Esc>:w<CR>a

" use ; as :
map ; :

"""""""""""""""""""""
"      Plugins      "
"""""""""""""""""""""

" ------------------------------------------------------------------
" vim-go
" ------------------------------------------------------------------
let g:go_fmt_command = "goimports"
let g:go_autodetect_gopath = 1
let g:go_list_type = "quickfix"
let g:go_snippet_engine = "neosnippet"

let g:go_highlight_types = 1
let g:go_highlight_fields = 1
let g:go_highlight_functions = 1
let g:go_highlight_methods = 1
let g:go_highlight_extra_types = 1
let g:go_highlight_generate_tags = 1

" Open :GoDeclsDir with ctrl-g
nmap <C-g> :GoDeclsDir<cr>
imap <C-g> <esc>:<C-u>GoDeclsDir<cr>

augroup go
  autocmd!

  " Show by default 4 spaces for a tab
  autocmd BufNewFile,BufRead *.go setlocal noexpandtab tabstop=2 shiftwidth=2

  " :GoBuild and :GoTestCompile
  autocmd FileType go nmap <leader>b :<C-u>call <SID>build_go_files()<CR>

  " :GoTest
  autocmd FileType go nmap <leader>t  <Plug>(go-test)
  " :GoTestFunc
  autocmd FileType go nmap <leader>f  <Plug>(go-test-func)

  " :GoRun
  autocmd FileType go nmap <leader>r  <Plug>(go-run)

  " :GoDoc
  autocmd FileType go nmap <Leader>d <Plug>(go-doc)

  " :GoCoverageToggle
  "autocmd FileType go nmap <Leader>c <Plug>(go-coverage-toggle)

  " :GoInfo
  autocmd FileType go nmap <Leader>i <Plug>(go-info)

  " :GoMetaLinter
  autocmd FileType go nmap <Leader>l <Plug>(go-metalinter)

  " :GoDef but opens in a vertical split
  autocmd FileType go nmap <Leader>v <Plug>(go-def-vertical)

  " :GoDef but opens in a horizontal split
  autocmd FileType go nmap <Leader>s <Plug>(go-def-split)

  " Show a list of interfaces which is implemented by the type under your cursor
  au FileType go nmap <Leader>s <Plug>(go-implements)

  " Show type info for the word under your cursor
  au FileType go nmap <Leader>i <Plug>(go-info)

  " Rename the identifier under the cursor to a new name
  au FileType go nmap <Leader>e <Plug>(go-rename)

  " :GoAlternate  commands :A, :AV, :AS and :AT
  autocmd Filetype go command! -bang A call go#alternate#Switch(<bang>0, 'edit')
  autocmd Filetype go command! -bang AV call go#alternate#Switch(<bang>0, 'vsplit')
  autocmd Filetype go command! -bang AS call go#alternate#Switch(<bang>0, 'split')
  autocmd Filetype go command! -bang AT call go#alternate#Switch(<bang>0, 'tabe')

  "let g:go_auto_sameids = 1

	au FileType go set foldmethod=syntax
	autocmd Filetype go normal zR

	" put quickfix window always to the bottom
	autocmd FileType qf wincmd J
augroup END

" build_go_files is a custom function that builds or compiles the test file.
" It calls :GoBuild if its a Go file, or :GoTestCompile if it's a test file
function! s:build_go_files()
  let l:file = expand('%')
  if l:file =~# '^\f\+_test\.go$'
    call go#cmd#Test(0, 1)
  elseif l:file =~# '^\f\+\.go$'
    call go#cmd#Build(0)
  endif
endfunction
" ------------------------------------------------------------------

" ------------------------------------------------------------------
" Taggbar settings
" ------------------------------------------------------------------
nmap <F8> :TagbarToggle<CR>
" ------------------------------------------------------------------

" ------------------------------------------------------------------
"  Neocomplete settings
" ------------------------------------------------------------------
let g:neocomplete#enable_at_startup = 1
" Auto select firt word
let g:neocomplete#enable_auto_select = 1
" Use smartcase.
let g:neocomplete#enable_smart_case = 1
" Set minimum syntax keyword length.
let g:neocomplete#min_keyword_length = 3

imap <expr><ESC> pumvisible() ? "\<C-e>" : "\<ESC>"
let g:neocomplete#auto_complete_delay=500
" ------------------------------------------------------------------

" ------------------------------------------------------------------
"  neosnippet settings
" ------------------------------------------------------------------

" Plugin key-mappings.
imap <C-k>     <Plug>(neosnippet_expand_or_jump)
smap <C-k>     <Plug>(neosnippet_expand_or_jump)
xmap <C-k>     <Plug>(neosnippet_expand_target)

" SuperTab like snippets behavior.
"\ neocomplete#complete_common_string() != '' ?
"\   neocomplete#complete_common_string() :
imap <expr><TAB>
\   pumvisible() ?
\     "\<C-y>" :
\     neosnippet#expandable_or_jumpable() ?
\       "\<Plug>(neosnippet_expand_or_jump)" : "\<TAB>"

smap <expr><TAB> neosnippet#expandable_or_jumpable() ?
\ "\<Plug>(neosnippet_expand_or_jump)" : "\<TAB>"

" For conceal markers.
if has('conceal')
  set conceallevel=1 concealcursor=niv
endif
" ------------------------------------------------------------------
let g:airline_powerline_fonts = 1

" ------------------------------------------------------------------
"  LeaderF mappings
" ------------------------------------------------------------------
nmap <C-F> :LeaderfSelf<cr>
nmap <C-f> :LeaderfFile<cr>


" ------------------------------------------------------------------
"  Syntastic settings
" ------------------------------------------------------------------
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0

nmap <leader>e :Errors<cr>
