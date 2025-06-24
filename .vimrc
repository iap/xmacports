" Vim configuration for development environment
" Optimized for macOS Catalina and legacy compatibility
" Follows system rules for minimal, secure, and reproducible setup

" Basic Settings
set nocompatible              " Disable vi compatibility
set encoding=utf-8            " Use UTF-8 encoding
set fileencoding=utf-8        " File encoding
set backspace=indent,eol,start " Allow backspace over everything

" Display Settings
set number                    " Show line numbers
set relativenumber            " Show relative line numbers
set ruler                     " Show cursor position
set showcmd                   " Show command in status line
set showmode                  " Show current mode
set laststatus=2              " Always show status line
set cursorline                " Highlight current line
set colorcolumn=80            " Show column at 80 characters

" Search Settings
set hlsearch                  " Highlight search results
set incsearch                 " Incremental search
set ignorecase                " Case insensitive search
set smartcase                 " Case sensitive if uppercase present

" Indentation Settings
set autoindent                " Auto indent new lines
set smartindent               " Smart indentation
set expandtab                 " Use spaces instead of tabs
set tabstop=4                 " Tab width
set shiftwidth=4              " Indent width
set softtabstop=4             " Soft tab width

" File Handling
set autoread                  " Auto reload changed files
set hidden                    " Allow hidden buffers
set backup                    " Enable backups
set writebackup               " Write backup before overwriting
set undofile                  " Persistent undo
set swapfile                  " Enable swap files

" Directory Settings (XDG compliant)
if exists('$XDG_CACHE_HOME')
    set backupdir=$XDG_CACHE_HOME/vim/backup//
    set directory=$XDG_CACHE_HOME/vim/swap//
    set undodir=$XDG_CACHE_HOME/vim/undo//
else
    set backupdir=$HOME/.cache/vim/backup//
    set directory=$HOME/.cache/vim/swap//
    set undodir=$HOME/.cache/vim/undo//
endif

" Create directories if they don't exist
if !isdirectory(expand(&backupdir))
    call mkdir(expand(&backupdir), 'p', 0700)
endif
if !isdirectory(expand(&directory))
    call mkdir(expand(&directory), 'p', 0700)
endif
if !isdirectory(expand(&undodir))
    call mkdir(expand(&undodir), 'p', 0700)
endif

" Performance Settings
set lazyredraw                " Don't redraw during macros
set ttyfast                   " Fast terminal connection
set updatetime=300            " Faster completion

" Security Settings
set modelines=0               " Disable modelines for security
set nomodeline                " Disable modeline parsing

" Syntax and Colors
syntax enable                 " Enable syntax highlighting
set background=dark           " Dark background
if has('termguicolors')
    set termguicolors         " True color support
endif

" Key Mappings
let mapleader = ","           " Set leader key

" Clear search highlighting
nnoremap <leader>/ :nohlsearch<CR>

" Quick save and quit
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>x :x<CR>

" Buffer navigation
nnoremap <leader>n :bnext<CR>
nnoremap <leader>p :bprev<CR>
nnoremap <leader>d :bdelete<CR>

" Window navigation
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" File type specific settings
augroup FileTypeSettings
    autocmd!
    " Shell scripts
    autocmd FileType sh,bash,zsh setlocal tabstop=2 shiftwidth=2 softtabstop=2
    " Configuration files
    autocmd FileType yaml,yml setlocal tabstop=2 shiftwidth=2 softtabstop=2
    autocmd FileType json setlocal tabstop=2 shiftwidth=2 softtabstop=2
    " Markdown
    autocmd FileType markdown setlocal wrap linebreak textwidth=80
    " Git commit messages
    autocmd FileType gitcommit setlocal textwidth=72 colorcolumn=72
augroup END

" Status Line (minimal)
set statusline=%f               " File name
set statusline+=%m              " Modified flag
set statusline+=%r              " Read-only flag
set statusline+=%=              " Right align
set statusline+=%l/%L           " Line number/total lines
set statusline+=\ %c            " Column number
set statusline+=\ %P            " Percentage through file

" Netrw Settings (built-in file explorer)
let g:netrw_banner = 0          " Hide banner
let g:netrw_liststyle = 3       " Tree view
let g:netrw_browse_split = 4    " Open in previous window
let g:netrw_altv = 1            " Open splits to the right
let g:netrw_winsize = 25        " 25% width

" Security: Disable potentially dangerous features
set secure                      " Secure mode for reading .vimrc in current dir
set noexrc                      " Don't read .vimrc in current directory

" Clipboard integration (macOS)
if has('clipboard')
    set clipboard=unnamed       " Use system clipboard
endif

" Load local customizations if they exist
if filereadable(expand('$HOME/.vimrc.local'))
    source $HOME/.vimrc.local
endif
