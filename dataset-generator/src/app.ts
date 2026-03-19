import puppeteer from 'puppeteer'
import { readFile, mkdir } from 'fs/promises'

// Set up Puppeteer browser and page
const browser = await puppeteer.launch({ headless: true })
const page = await browser.newPage()

// Load contents
const content = await readFile('src/content.html')
const style = await readFile('src/style.css')
const script = await readFile('src/script.js')

// Set page html content with styles and scripts
const htmlContent = content.toString().replace(`<link rel="stylesheet" href="./style.css">`, `<style>\n${style.toString()}\n</style>`).replace(`<script src="./script.js"></script>`, `<script>${script.toString()}</script>`)
await page.setContent(htmlContent)

const generateTileDataset = async (value: string, onBoard: boolean, onRack: boolean) => {
  // Create the value directory
  const currentValueDirPath = `./output/${value == ' ' ? 'EMPTY' : value}/`
  await mkdir(currentValueDirPath, { recursive: true })
  console.log(`Generating versions of "${value}"`)

  const ITERATION_COUNT = 1000
  for (let i = 0; i < ITERATION_COUNT; i++) {
    // Randomize grid scale
    const scale = Math.random() + 0.5
    const gridElement = await page.$('.grid')
    await page.evaluate(
      (gridElement, scale) => {
        gridElement.style.transform = `scale(${scale})`
      },
      gridElement,
      scale
    )

    // Randomize surrounding tile states
    await page.evaluate(
      (value, onBoard, onRack) => {
        // @ts-ignore - This is a function within the website
        updateVisualization(value, onBoard, onRack)
      },
      value,
      onBoard,
      onRack
    )

    // Wiggle camera position
    const cameraElement = await page.$('.camera')
    await page.evaluate(
      (cameraElement, scale) => {
        const deltaX = (Math.round(Math.random() * 26) - 13) * scale
        const deltaY = (Math.round(Math.random() * 26) - 13) * scale
        cameraElement.style.transform = `translate(${deltaX}px, ${deltaY}px)`
      },
      cameraElement,
      scale
    )

    await cameraElement?.screenshot({ path: `${currentValueDirPath}${Bun.randomUUIDv7()}.png` })
    console.log(`Iteration ${i + 1} / ${ITERATION_COUNT} for "${value}"`)
  }
}

// Generate board only tiles
for (const value of ['TW', 'DW', 'TL', 'DL']) {
  await generateTileDataset(value, true, false)
}

// Generate rack only tiles
for (const value of ['?']) {
  await generateTileDataset(value, false, true)
}

// Generate board and rack tiles
for (const value of ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'Å', 'Ä', 'Ö', 'EMPTY']) {
  await generateTileDataset(value, true, true)
}

await browser.close()
console.log('Completed!')
