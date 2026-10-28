export const petThemes=Object.freeze({
 'sakura-calm-soft-portrait':{sprite:'sakura-soft-bust.png',preview:'/assets/sakura-soft-pet.png',name:'柔光格裙Q版'}
});
export function petTheme(id){const theme=petThemes[id];if(!theme)throw Error('未知桌宠主题');return theme;}
