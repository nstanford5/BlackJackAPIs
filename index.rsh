'reach 0.1';

const [isOut, P_WINS, D_WINS, DRAW] = makeEnum(3);

// todo: implement limit on wager amount (frontend? given from Dealer?)
const DEADLINE = 20;
const LENGTH = 15;// in blocks
const BANK = 9000;
const cardValue = (x) => (x < 10 ? x : 10);
const myFromMaybe = (m) => fromMaybe(m, (() => 0), ((x) => x))
const winner = (pTotal, dTotal) => {
  if(pTotal > 21 || (dTotal < 22 && dTotal > pTotal)){
    return D_WINS;
  } else {
    if(pTotal < 22 && (pTotal > dTotal || dTotal > 21)){
      return P_WINS;
    } else if (pTotal == dTotal){
      return DRAW;
    } else return D_WINS;
  }
};// end of winner
assert(winner(20, 21) == D_WINS);
assert(winner(22, 15) == D_WINS);
assert(winner(19, 17) == P_WINS);
assert(winner(21, 20) == P_WINS);
assert(winner(14, 25) == P_WINS);
assert(winner(18, 18) == DRAW);
assert(winner(21, 21) == DRAW);
assert(winner(22, 22) == D_WINS);

forall(UInt, x => 
  forall(UInt, y => 
    assert(isOut(winner(x, y)))));

// this isn't actually what we assume is true about this function
// if pTotal > 21 they lose even if dTotal > 21
// forall(UInt, x => 
//     assert(winner(x, x) == DRAW));

export const main = Reach.App(() => {
  setOptions({ untrustworthyMaps: true });
  const D = Participant('Dealer', {
    ...hasRandom,
    bank: UInt,
    ready: Fun([], UInt),
    getCard: Fun([], UInt),
    showCards: Fun([Address, UInt, UInt], Null),
    showTotalA: Fun([Address, UInt], Null),
    //showTotalB: Fun([Address, UInt], Null),
    showBalance: Fun([UInt], Null),
  });
  const P = API('Player', {
    // inputWager: Fun([UInt], Null), <-- show how you would have to write this
    //        function if not for pay abstraction in return of api call
    startGame: Fun([UInt, UInt, UInt], Object({
      addr: Address, amt: UInt, c1: UInt, c2: UInt, total: UInt, cardCount: UInt,
    })),
    getCard: Fun([UInt], Object({
      addr: Address, amt: UInt, c1: UInt, c2: UInt, total: UInt, cardCount: UInt,
    })),
    checkWin: Fun([], UInt),
    timesUp: Fun([], Bool),
  });
  const V = View('V', {
    vDealer: Address,
    vBank: UInt,
    getPlayer: Fun([Address], Object({
      amt: UInt, c1: UInt, c2: UInt, total: UInt, cardCount: UInt,
    }))
  });
  init();

  D.only(() => {
    const  _dCard = interact.ready();
    const [_commitD, _saltD ] = makeCommitment(interact, _dCard);
    const commitD = declassify(_commitD);
    const dCard2 = declassify(interact.getCard());
    const bank = declassify(interact.bank);
    check(bank > 2000, 'bank too low');
  })

  D.publish(commitD, dCard2, bank)
    .pay(bank);
  commit();
  D.interact.showBalance(balance());
  D.publish();
  
  const payBank = BANK / 10;
  
  const players = new Map(Address, Object({
    addr: Address,
    amt: UInt,
    c1: UInt,
    c2: UInt,
    total: UInt,
    cardCount: UInt,
  }));
  const pSet = new Set();
  const wagerMap = new Map(Address, UInt);
  V.vDealer.set(D);
  V.vBank.set(bank);
  const [ count, wagers ] = parallelReduce([ 0, 0 ])
    .invariant(balance() == (wagers + bank))
    .while(count < 4)
    .api_(P.startGame, (card1, card2, wager) => {
      check(wager < 101000000, 'sorry, that wager is over the limit');
      return[wager, (ret) => {
        D.interact.showBalance(balance());
        const who = this;
        pSet.insert(who);
        wagerMap[who] = wager;
        require(pSet.member(this));
        const sum = add(cardValue(card1), cardValue(card2));
        players[who] = {
          addr: who,
          amt: wager,
          c1: card1,
          c2: card2,
          total: sum,
          cardCount: 2,
        };
        /**
         * players[who] is an optional type, a Maybe value.
         * It is either None or Some, depending on contents. You need to consume
         * the Some value with fromSome which takes 2 arguments (Maybe, default if None)
         */
        ret(fromSome(players[who],
          { addr: who, amt: wager, c1: card1, c2: card2, total: sum, cardCount: 2 }));
          return[ (sum < 14 ? count : count + 1), wagers + wager ];
      }];
    })
    .api_(P.getCard, (nCard) => {
      return[0, (ret) => {
        // this doesn't work. I think its because it can be called by someone not in the list?
        //check(pSet.member(this), "sorry, not in the list");
        const who = this;
        const pObj = fromSome(players[who],
          {addr: this, amt: 0, c1: 0, c2: 0, total: 0, cardCount: 0});
        const total = pObj.total + cardValue(nCard);
        players[who] = {
          addr: who,
          amt: pObj.amt,
          c1: pObj.c1,
          c2: pObj.c2,
          total: total,
          cardCount: (pObj.cardCount + 1),
        };
        ret(fromSome(players[who], {
          addr: who,
          amt: pObj.amt,
          c1: pObj.c1,
          c2: pObj.c2,
          total: total,
          cardCount: pObj.cardCount,
        }));
        return [ (total < 14 ? count : count + 1), wagers ];
      }];
    })
    .timeout(relativeTime(DEADLINE), () => {
      const [[], ret] = call(P.timesUp);
      ret(true);
      return[count, wagers];
    })
  commit();
  D.only(() => {
    const saltD = declassify(_saltD);
    const dCard = declassify(_dCard);
    interact.showCards(this, dCard, dCard2);
  });
  D.publish(saltD, dCard);
  checkCommitment(commitD, saltD, dCard);

  var [
    dTotal, 
    dAces,
    keepGoing 
  ]  =  [
    cardValue(dCard) + cardValue(dCard2), 
    (dCard == 1 ? 1 : 0) + (dCard2 == 1 ? 1 : 0),
    true
  ];
  invariant(balance() == (bank + wagers));
  while(keepGoing){
    if(dTotal > 21 && dAces > 0){
      commit();
      D.publish();
      [dTotal, dAces, keepGoing] = [dTotal - 1, dAces - 1, true];
      continue;
    } else {
      if(dTotal < 17){
        commit();
        D.only(() => {
          const nCard = declassify(interact.getCard());
        })
        D.publish(nCard); 
        [dTotal, dAces, keepGoing] = [add(dTotal, cardValue(nCard)), dAces + (nCard == 1 ? 1 : 0), true];
        continue;
      } else {
        // should I publish the state here? A num to represent array index
        commit();
        D.publish();
        keepGoing = false;
        continue;
      }
    }
  }
  D.interact.showBalance(balance());
  D.interact.showTotalA(D, dTotal);
  const [fCount, nWagers] = parallelReduce([count, wagers])
    .invariant(true)
    .while(fCount > 0)
    .api(P.checkWin,
      () => {
        check(pSet.member(this), "Sorry, you didn't wager");
        check(balance() > 1000, 'balance too low');
        assume(myFromMaybe(wagerMap[this]) < 101, 'assume wager too high')
      },
      () => 0,
      (ret) => {
        const who = this;
        const pObj = fromSome(players[who],
          {addr: who, amt: 0, c1: 0, c2: 0, total: 0, cardCount: 0});
        D.interact.showBalance(pObj.amt);// temp display wager amount
        const win = winner(pObj.total, dTotal);
        ret(win);
        const bet = myFromMaybe(wagerMap[this]);
        require(bet < 101, 'bet too high');
        const betBal = ((balance() - (wagers + bank) + bet));
        delete wagerMap[this];
        if(win == P_WINS){
          // check for 21
          if(pObj.total == 21 && pObj.cardCount == 2){
            // blackjack win amount
            //transfer(bet).to(who);
            return [fCount - 1, nWagers - bet]
          } else {
            // regular win amount
            //transfer(bet).to(who);
            return[fCount - 1, nWagers - bet];
          }
        } else {
          if(win == DRAW){
            // return the users bet
            //transfer(bet).to(who);
            return[fCount - 1, nWagers - bet];
          } else {
            // you lose
            return[fCount - 1, nWagers - bet];
          }
        }
      })
  transfer(balance()).to(D);
  commit();
  exit();
});
