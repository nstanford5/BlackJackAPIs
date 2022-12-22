import { loadStdlib } from '@reach-sh/stdlib'
import * as backend from './build/index.main.mjs'
const stdlib = loadStdlib({ REACH_NO_WARN: 'Y' })

const startingBalance = stdlib.parseCurrency(1000)
const accDealer = await stdlib.newTestAccount(stdlib.parseCurrency(10000))

const deck = {
	1: 'A',
	2: '2',
	3: '3',
	4: '4',
	5: '5',
	6: '6',
	7: '7',
	8: '8',
	9: '9',
	10: '10',
	11: 'J',
	12: 'Q',
	13: 'K',
}
const choices = ['Stay', 'Hit']
const outcomes = ['Player wins', 'Dealer wins', 'Draw']

console.log("Hello Players! Have a seat, let's play blackjack!")

console.log('Launching...')
const ctcDealer = accDealer.contract(backend)

const drawCard = () => {
	const c = Math.floor(Math.random() * 12) + 1
	return c
}
const fmt = (x) => stdlib.formatCurrency(x, 4)
const cardValue = (x) => (x < 10 ? x : 10)
const getBalance = async (who) => fmt(await stdlib.balanceOf(who))
const beforeDealer = await getBalance(accDealer)
let pAcc = []

const startPlayers = async () => {
	const runPlayers = async (who) => {
		let cards = []
		const acc = await stdlib.newTestAccount(startingBalance)
		const ctc = acc.contract(backend, ctcDealer.getInfo())
		pAcc.push([who, ctc, acc])
		//const accBefore = await getBalance(acc);
		const hand = {
			card1: drawCard(),
			card2: drawCard(),
			wager: stdlib.parseCurrency(Math.floor(Math.random() * 90) + 10),
		}
		cards.push(deck[hand.card1])
		cards.push(deck[hand.card2])
		console.log(
			`Having Player ${who} pay a wager of ${fmt(
				hand.wager
			)}`
		)
		const pObj = await ctc.apis.Player.startGame(
			hand.card1,
			hand.card2,
			hand.wager
		)

		// this returns [some, microUnits] for vBank
		const num = await ctc.views.V.vBank()
		console.log(`View Test ${stdlib.formatCurrency(num[1])}`)
		while (pObj.total < 14) {
			const nCard = drawCard()
			cards.push(deck[nCard])
			const nObj = await ctc.apis.Player.getCard(nCard)
			pObj.total = nObj.total
			pObj.cardCount = nObj.cardCount
		} // end of while
		console.log(`Player summary of: ${stdlib.formatAddress(pObj.addr)}
       Wager: ${stdlib.formatCurrency(pObj.amt)}
       Cards: ${cards.join(' ')}
       Total: ${pObj.total}
       Count: ${pObj.cardCount}`)
	} // end of runPlayers
	await runPlayers('One')
	await runPlayers('Two')
	await runPlayers('Three')
	await runPlayers('Four')
} // end of startPlayers.

const checkWin = async () => {
	for (const [who, ctc, _] of pAcc) {
		try {
			const b = await ctc.apis.Player.checkWin()
			console.log(`Player ${who} outcome is ${outcomes[b]}`)
		} catch (e) {
			console.log(`${e}`)
		}
	}
}

console.log('Starting backends...')
await Promise.all([
	backend.Dealer(ctcDealer, {
		...stdlib.hasRandom,
		bank: stdlib.parseCurrency(9000),
		ready: async () => {
			startPlayers()
			return drawCard()
		},
		getCard: () => {
			const c = drawCard()
			console.log(`Dealer drew a ${deck[c]}`)
			return c
		},
		showCards: (who, c1, c2) => {
			if (who === accDealer.getAddress()) {
				console.log(`Dealer cards are ${deck[c1]} and ${deck[c2]}`)
			} else {
				const sum = cardValue(parseInt(c1)) + cardValue(parseInt(c2))
				console.log(`${stdlib.formatAddress(who)} drew a ${deck[c1]} and ${
					deck[c2]
				}
          for a total of ${sum}`)
			}
		},
		showTotalA: async (who, sum) => {
			if (who === accDealer.getAddress()) {
				console.log(`Dealer total is ${parseInt(sum)}`)
			} else {
				console.log(
					`Get Card total of ${stdlib.formatAddress(who)} cards is ${parseInt(
						sum
					)}`
				)
			}
			checkWin()
		},
		showBalance: (bal) => {
			console.log(`Balance total: ${stdlib.formatCurrency(bal)}`)
		},
	}),
])
console.log('Casino is closing!')
console.log(
	`Dealer final balance: ${await getBalance(accDealer)} ${stdlib.standardUnit}`
)
console.log("Players' final balances...")
for (const [who, _, acc] of pAcc) {
	console.log(
		`Player ${who}'s final balance: ${await getBalance(acc)} ${stdlib.standardUnit}`
	)
}