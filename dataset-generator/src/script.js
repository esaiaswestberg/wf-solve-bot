// Helper function to shuffle an array
const shuffleArray = (array) => {
  for (let i = array.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    ;[array[i], array[j]] = [array[j], array[i]]
  }
  return array
}

// Possible tile values
const boardOnly = ['TW', 'DW', 'TL', 'DL']
const rackOnly = ['?']
const boardAndRack = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'Å', 'Ä', 'Ö', 'EMPTY']

// Find all tile elements
const tilePositionClasses = ['ptl', 'ptc', 'ptr', 'pcl', 'pcc', 'pcr', 'pbl', 'pbc', 'pbr']
const tileElements = tilePositionClasses.map((classname) => document.querySelector(`.${classname}`))

// Set the value of a tile
const setTileValue = (tile, value, racked) => {
  // Clear earlier classes
  tile.classList.remove('dw', 'tw', 'dl', 'tl', 'empty')

  // Add a modifier class 20% of the time, if on the board
  if (Math.random() < 0.2 && !racked && !value) {
    const modifier = shuffleArray(['dw', 'tw', 'dl', 'tl'])[0]
    tile.classList.add(modifier)
  }

  // Make non valued tile empty 60% of the time
  if (Math.random() < 0.6 && !value) {
    tile.classList.add('empty')
    return
  }

  // Randomize value if none is provided
  if (value == null) {
    const possibleValues = [...boardAndRack]

    if (racked) possibleValues.push(...rackOnly)
    else possibleValues.push(...boardOnly)

    value = shuffleArray(possibleValues)[0]
  }

  // Randomize a score
  const scoreValue = Math.ceil(Math.random() * 9)

  // Update the value of the tile
  switch (value) {
    case 'EMPTY':
      tile.classList.add('empty')
      break
    case '?':
      tile.querySelector('.letter').textContent = ''
      tile.querySelector('.score').textContent = ''
      break
    case 'TL':
    case 'DL':
    case 'DW':
    case 'TW':
      tile.classList.add(value.toLowerCase(), 'empty')
      tile.querySelector('.letter').textContent = ''
      tile.querySelector('.score').textContent = ''
      break
    default:
      tile.querySelector('.letter').textContent = value

      // Normal letter tiles should 10% of the time, have no score
      if (Math.random() < 0.1) tile.querySelector('.score').textContent = ''
      else tile.querySelector('.score').textContent = scoreValue

      break
  }
}

// Update the visualization to a valid, but random scenario
const updateVisualization = (value, onBoard, onRack) => {
  // Randomize between possible states
  const state = shuffleArray([onBoard ? 'board' : null, onRack ? 'rack' : null].filter(Boolean))[0]

  // Only show the middle row when state is rack, show all otherwise
  if (state == 'rack') {
    // Hide top and bottom rows
    ;[...tileElements.slice(0, 3), ...tileElements.slice(6, 9)].forEach((tile) => tile.classList.add('hidden'))

    // Show middle row
    tileElements.slice(3, 6).forEach((tile) => tile.classList.remove('hidden'))

    // Add rack background styling
    tileElements[4].classList.add('rack')
    tileElements[4].classList.remove('left', 'right')

    // There is a 15% chance we're on an edge
    if (Math.random() < 0.15 || true) {
      // Randomize if we're on the left or right
      if (Math.random() < 0.5) {
        tileElements[3].classList.add('hidden')
        tileElements[4].classList.add('left')
      } else {
        tileElements[5].classList.add('hidden')
        tileElements[4].classList.add('right')
      }
    }
  } else {
    // By default, show all when on board
    tileElements.forEach((tile) => tile.classList.remove('hidden'))

    // Remove rack styling
    tileElements[4].classList.remove('rack', 'left', 'right')

    // There is a 5% chance we're on a corner
    if (Math.random() < 0.05) {
      const corner = shuffleArray(['tl', 'tr', 'bl', 'br'])[0]
      if (corner == 'tl') [...tileElements.slice(0, 3), tileElements[3], tileElements[6]].forEach((tile) => tile.classList.add('hidden'))
      if (corner == 'tr') [...tileElements.slice(0, 3), tileElements[5], tileElements[8]].forEach((tile) => tile.classList.add('hidden'))
      if (corner == 'bl') [...tileElements.slice(6, 9), tileElements[0], tileElements[3]].forEach((tile) => tile.classList.add('hidden'))
      if (corner == 'br') [...tileElements.slice(6, 9), tileElements[2], tileElements[5]].forEach((tile) => tile.classList.add('hidden'))
    }
  }

  // Set center value
  setTileValue(tileElements[4], value, state == 'rack')

  // Randomize all surrounding values
  tileElements.forEach((tile, index) => {
    if (index != 4) {
      setTileValue(tile, null, state == 'rack')
    }
  })
}
