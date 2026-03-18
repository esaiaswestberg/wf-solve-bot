const shuffleArray = (array) => {
  for (let i = array.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [array[i], array[j]] = [array[j], array[i]];
  }
  return array;
};

const surroundingElementClasses = ['ptl','ptc','ptr','pcl','pcr','pbl','pbc','pbr']
const surroundingElements = surroundingElementClasses.map((classname) => document.querySelector(`.${classname}`))

const possibleStates = [...('ABCDEFGHIJKLMNOPQRSTUVWXYZÅÄÖ'.split('')), 'TW', 'DW', 'TL', 'DL']
const secondaryStates = ['TW', 'DW', 'TL', 'DL', '', '', '', '', '', '', '', '', '', '', '', '']
const randomizeSurroundingTiles = () => {
    surroundingElements.forEach((tile) => {
        // Randomize state
        const state = shuffleArray(possibleStates)[0]
        const secondaryState = state.length == 2 ? false : shuffleArray(secondaryStates)[0]

        // Set tile classes
        if (state.length == 2) tile.classList.add('empty', state.toLowerCase())
        else tile.classList.remove('empty', 'tw', 'dw', 'tl', 'dl')

        // Set secondary state classes
        if (secondaryState) tile.classList.add(secondaryState.toLowerCase())

        // Set letter if not special state
        if (state.length == 1) tile.querySelector('.letter').innerHTML = state

        // Set random score value
        const score = Math.round(Math.random() * 10)
        tile.querySelector('.score').innerHTML = score ? score : ''
    })
}

//setInterval(randomizeSurroundingTiles, 25)