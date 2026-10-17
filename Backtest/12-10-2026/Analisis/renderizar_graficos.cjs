const fs=require('fs');
const path=require('path');
const sharp=require('C:/Users/Dany/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
(async()=>{for(const f of fs.readdirSync(__dirname).filter(f=>f.endsWith('.svg'))){await sharp(path.join(__dirname,f),{density:150}).flatten({background:'#ffffff'}).png().toFile(path.join(__dirname,f.replace('.svg','.png')));} console.log('9 gráficos PNG renderizados.');})().catch(e=>{console.error(e);process.exit(1)});
