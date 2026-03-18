import puppeteer from "puppeteer";
import { readFile, mkdir } from 'fs/promises'

const browser = await puppeteer.launch({ headless: true })
const page = await browser.newPage()
const content = await readFile('src/content.html');
const style = await readFile('src/style.css')
const script = await readFile('src/script.js')
const htmlContent = content.toString()
    .replace(
        `<link rel="stylesheet" href="./style.css">`,
        `<style>\n${style.toString()}\n</style>`
    )
    .replace(
        `<script src="./script.js"></script>`,
        `<script>${script.toString()}</script>`
    )

await page.setContent(htmlContent);

const letters = [...('ABCDEFGHIJKLMNOPQRSTUVWXYZÅÄÖ? '.split('')), 'TW', 'DW', 'TL', 'DL']
for (const letter of letters) {
    // Create the letter directory
    const letterDirPath = `./output/${letter == ' ' ? 'EMPTY' : letter}/`
    await mkdir(letterDirPath, { recursive: true })
    console.log(`Generating versions of "${letter}"`)

    const ITERATION_COUNT = 100;
    for (let i = 0; i < ITERATION_COUNT; i++) {
        // Randomize surrounding tile states
        await page.evaluate(() => {
            randomizeSurroundingTiles()
        })

        // Set the center tile content
        const pcc = await page.$(".pcc")
        await page.evaluate((pcc, letter) => {
            // Set letter value
            let symbol = letter
            if (letter == '?' || letter.length == 2) symbol = ''

            pcc.querySelector('.letter').innerHTML = symbol;

            // Set score value and opacity
            let score = Math.round(Math.random() * 10)
            if (letter.length > 1 || letter == '?' || letter == ' ') score = 0;

            pcc.querySelector('.score').innerHTML = score;
            pcc.querySelector('.score').style.opacity = score > 0 ? 1 : 0;

            // Set special values
            pcc.classList.remove('dl', 'tl', 'dw', 'tw', 'empty')
            if (letter.length == 2) pcc.classList.add(letter.toLowerCase(), 'empty')
            if (letter == ' ') pcc.classList.add('empty')
        }, pcc, letter);

        // Wiggle camera position
        const element = await page.$(".camera");
        await page.evaluate((el) => {
            const deltaX = Math.round(Math.random() * 26) - 13
            const deltaY = Math.round(Math.random() * 26) - 13
            el.style.transform = `translate(${deltaX}px, ${deltaY}px)`
        }, element);

        await element?.screenshot({ path: `${letterDirPath}${Bun.randomUUIDv7()}.png` })
        console.log(`Iteration ${i + 1} / ${ITERATION_COUNT} for "${letter}"`)
    }
}

await browser.close()
console.log('Completed!')