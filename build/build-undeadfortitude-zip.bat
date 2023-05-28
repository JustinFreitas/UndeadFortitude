:: Assumes running from UndeadFortitude\build
mkdir out\UndeadFortitude
copy ..\extension.xml out\UndeadFortitude\
copy ..\readme.txt out\UndeadFortitude\
copy ..\"Open Gaming License v1.0a.txt" out\UndeadFortitude\
mkdir out\UndeadFortitude\graphics\icons
copy ..\graphics\icons\undeadfortitude_icon.png out\UndeadFortitude\graphics\icons\
copy ..\graphics\icons\white_undeadfortitude_icon.png out\UndeadFortitude\graphics\icons\
mkdir out\UndeadFortitude\campaign
copy ..\campaign\ct_host.xml out\UndeadFortitude\campaign\
mkdir out\UndeadFortitude\scripts
copy ..\scripts\undeadfortitude.lua out\UndeadFortitude\scripts\
copy ..\scripts\ct_host_ct_entry.lua out\UndeadFortitude\scripts\
cd out
CALL ..\zip-items UndeadFortitude
rmdir /S /Q UndeadFortitude\
copy UndeadFortitude.zip UndeadFortitude.ext
cd ..
explorer .\out
