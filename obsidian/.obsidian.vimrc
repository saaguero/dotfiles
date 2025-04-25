" Inspirations from:
" https://github.com/esm7/obsidian-vimrc-support
" https://github.com/chrisgrieser/.config/blob/main/obsidian/vimrc/obsidian-vimrc.vim

" free <space> to be used as a <leader>
unmap <Space>

" remove search highlights
map <Space><CR> :nohl<cr>

" yank to system clipboard
set clipboard=unnamed

" navigate visual lines rather than logical ones
nnoremap j gj
nnoremap k gk
nnoremap <Down> gj
nnoremap <Up> gk
nnoremap I g0i
nnoremap A g$a

" emulate original gt and gT
exmap nextTab obcommand workspace:next-tab
exmap prevTab obcommand workspace:previous-tab
exmap undoTab obcommand workspace:undo-close-pane
nmap gt :nextTab<cr>
nmap gT :prevTab<cr>
nmap gr :undoTab<cr>

" emulate Original Folding command
exmap unfoldall obcommand editor:unfold-all
exmap togglefold obcommand editor:toggle-fold
exmap foldall obcommand editor:fold-all
exmap foldless obcommand editor:fold-less
exmap foldmore obcommand editor:fold-more
nmap zo :togglefold<cr>
nmap zc :togglefold<cr>
nmap za :togglefold<cr>
nmap zm :foldmore<cr>
nmap zM :foldall<cr>
nmap zr :foldless<cr>
nmap zR :unfoldall<cr>

" context menu
exmap contextMenu obcommand editor:context-menu
nmap z= :contextMenu<cr>
vmap z= :contextMenu<cr>

" close tab
exmap wq obcommand workspace:close
exmap q obcommand workspace:close

" easy pane navigation
exmap focusRight obcommand editor:focus-right
nmap <C-w>l :focusRight<cr>
exmap focusLeft obcommand editor:focus-left
nmap <C-w>h :focusLeft<cr>
exmap focusTop obcommand editor:focus-top
nmap <C-w>k :focusTop<cr>
exmap focusBottom obcommand editor:focus-bottom
nmap <C-w>j :focusBottom<cr>

" easy pane split
exmap vsplit obcommand workspace:split-vertical
nmap <C-w>v :vsplit<cr>
exmap split obcommand workspace:split-horizontal
nmap <C-w>s :split<cr>

" surround like mappings
exmap surround_link surround [[ ]]
exmap surround_higlight surround == ==
exmap surround_italics surround * *
exmap surround_bold surround ** **
exmap surround_double_quotes surround " "
exmap surround_single_quotes surround ' '
exmap surround_backticks surround ` `
exmap surround_brackets surround ( )
exmap surround_square_brackets surround [ ]
exmap surround_curly_brackets surround { }

nunmap s
vunmap s
map sl :surround_link<CR>
map sh :surround_higlight<CR>
map si :surround_italics<CR>
map sb :surround_bold<CR>
map s" :surround_double_quotes<CR>
map s' :surround_single_quotes<CR>
map s` :surround_backticks<CR>
map s( :surround_brackets<CR>
map s) :surround_brackets<CR>
map s[ :surround_square_brackets<CR>
map s] :surround_square_brackets<CR>
map s{ :surround_curly_brackets<CR>
map s} :surround_curly_brackets<CR>

" follow link, needs obsidian-shukuchi extension
exmap followNextLink obcommand shukuchi:open-link
nnoremap gx :followNextLink<cr>
nnoremap ga :followNextLink<cr>
nnoremap gd :followNextLink<cr>
nnoremap <C-]> :followNextLink<cr>

" language tool extension mappings
exmap languagetool_check obcommand languagetool:check
exmap languagetool_toggle_check obcommand languagetool:toggle-auto-check
exmap languagetool_clear obcommand languagetool:clear
exmap languagetool_next obcommand languagetool:next
exmap languagetool_accept1 obcommand languagetool:accept-1
exmap languagetool_synonyms obcommand languagetool:synonyms

nnoremap <Space>sc :languagetool_check<cr>
nnoremap <Space>st :languagetool_toggle_check<cr>
nnoremap <Space>sd :languagetool_clear<cr>
nnoremap <Space>sn :languagetool_next<cr>
vnoremap <Space>sn :languagetool_next<cr>
nnoremap <Space>sa :languagetool_accept1<cr>
vnoremap <Space>sa :languagetool_accept1<cr>
nnoremap <Space>sy :languagetool_synonyms<cr>
