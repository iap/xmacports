" Vim configuration

set nocompatible              " Disable vi compatibility
set encoding=utf-8            " Use UTF-8 encoding
set fileencoding=utf-8        " File encoding
set backspace=indent,eol,start " Allow backspace over everything

set number                    " Show line numbers
set relativenumber            " Show relative line numbers
set ruler                     " Show cursor position
set showcmd                   " Show command in status line
set showmode                  " Show current mode
set laststatus=2              " Always show status line
set cursorline                " Highlight current line
set colorcolumn=80            " Show column at 80 characters

set hlsearch                  " Highlight search results
set incsearch                 " Incremental search
set ignorecase                " Case insensitive search
set smartcase                 " Case sensitive if uppercase present

set autoindent                " Auto indent new lines
set smartindent               " Smart indentation
set expandtab                 " Use spaces instead of tabs
set tabstop=4                 " Tab width
set shiftwidth=4              " Indent width
set softtabstop=4             " Soft tab width

set autoread                  " Auto reload changed files
set hidden                    " Allow hidden buffers
set backup                    " Enable backups
set writebackup               " Write backup before overwriting
set undofile                  " Persistent undo
set swapfile                  " Enable swap files

if exists('$XDG_CACHE_HOME')
    set backupdir=$XDG_CACHE_HOME/vim/backup//
    set directory=$XDG_CACHE_HOME/vim/swap//
    set undodir=$XDG_CACHE_HOME/vim/undo//
else
    set backupdir=$HOME/.cache/vim/backup//
    set directory=$HOME/.cache/vim/swap//
    set undodir=$HOME/.cache/vim/undo//
endif

if !isdirectory(expand(&backupdir))
    call mkdir(expand(&backupdir), 'p', 0700)
endif
if !isdirectory(expand(&directory))
    call mkdir(expand(&directory), 'p', 0700)
endif
if !isdirectory(expand(&undodir))
    call mkdir(expand(&undodir), 'p', 0700)
endif

set lazyredraw                " Don't redraw during macros
set ttyfast                   " Fast terminal connection
set updatetime=300            " Faster completion

set modelines=0               " Disable modelines for security
set nomodeline                " Disable modeline parsing

syntax enable                 " Enable syntax highlighting
set background=dark           " Dark background
if has('termguicolors')
    set termguicolors         " True color support
endif

let mapleader = ","           " Set leader key

nnoremap <leader>/ :nohlsearch<CR>

nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>x :x<CR>

nnoremap <leader>n :bnext<CR>
nnoremap <leader>p :bprev<CR>
nnoremap <leader>d :bdelete<CR>

nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

augroup FileTypeSettings
    autocmd!
    autocmd FileType sh,bash,zsh setlocal tabstop=2 shiftwidth=2 softtabstop=2
    autocmd FileType yaml,yml setlocal tabstop=2 shiftwidth=2 softtabstop=2
    autocmd FileType json setlocal tabstop=2 shiftwidth=2 softtabstop=2
    autocmd FileType markdown setlocal wrap linebreak textwidth=80
augroup END

set statusline=%f               " File name
set statusline+=%m              " Modified flag
set statusline+=%r              " Read-only flag
set statusline+=%=              " Right align
set statusline+=%l/%L           " Line number/total lines
set statusline+=\ %c            " Column number
set statusline+=\ %P

let g:netrw_banner = 0          " Hide banner
let g:netrw_liststyle = 3       " Tree view
let g:netrw_browse_split = 4    " Open in previous window
let g:netrw_altv = 1            " Open splits to the right
let g:netrw_winsize = 25        " 25% width

set secure                      " Secure mode for reading .vimrc in current dir
set noexrc                      " Don't read .vimrc in current directory

if has('clipboard')
    set clipboard=unnamed       " Use system clipboard
endif

if filereadable(expand('$HOME/.vimrc.local'))
    source $HOME/.vimrc.local
endif

if exists('$XDG_CONFIG_HOME') && filereadable(expand('$XDG_CONFIG_HOME/vim/privacy.vim'))
    source $XDG_CONFIG_HOME/vim/privacy.vim
endif
