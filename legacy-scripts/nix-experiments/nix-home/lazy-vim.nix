{ pkgs, ... }:
{
  environment.variables = { EDITOR = "vim"; };
 
  environment.systemPackages = with pkgs; [
    ((vim-full.override {  }).customize{
      name = "vim-with-plugins";
      # Install plugins for example for syntax highlighting of nix files
      vimrcConfig.packages.myplugins = with pkgs.vimPlugins; {
        start = [
          lightline-vim
          fzfWrapper
          vim-visual-multi
          vim-surround
          nerdtree
          coc-nvim
          auto-pairs
          gruvbox
          vim-cmake
        ];
        opt = [];
      };
    #   vimrcConfig.customRC = ''
    #     set laststatus=2
    #     set nocompatible
    #     set backspace=indent,eol,start
    #     syntax on
    #     set nu
    #     set termguicolors
    #     colo gruvbox
    #
    #     inoremap <c-b> <Esc>:NERDTreeToggle<cr>
    #     nnoremap <c-b> <Esc>:NERDTreeToggle<cr>
    #
    #     " use <tab> to trigger completion and navigate to the next complete item
    #     function! CheckBackspace() abort
    #     let col = col('.') - 1
    #     return !col || getline('.')[col - 1]  =~# '\s'
    #     endfunction
    #
    #     inoremap <silent><expr> <Tab>
    #           \ coc#pum#visible() ? coc#pum#next(1) :
    #           \ CheckBackspace() ? "\<Tab>" :
    #           \ coc#refresh()
    #   '';
    # }
  )];
}
