## Lottery EtherThousands that follows the rules of the EuroMillions

# How is it played?

- A player must choose 7 numbers:
  - 5 numbers from a grid of 50 numbers (1 -> 50)
  - 2 numbers(stars) from a grid of 12 numbers (1 -> 12)
- You win the jackpot if you have the 5 numbers you chose and the 2 stars

# How is the jackpot set?

- The minimum jackpot is set at 17M euros in our case it will be 17K ether
- As long as there is no winner the jackpot gets bigger after every lottery till it reaches 250K ether(the ceiling)

# How to participate in a lottery?

- There are 2 ways to play:
  - Single-chance:
    - 1 simple grid
    - The simple grid costs 25 ether
    - The simple grid contains 5 numbers (1 -> 50) and 2 stars (1 -> 12)
  - Multi-chance:
    - Pack of 10 multi-grids
    - The pack is at 50 ether
    - Each of the multi-grid contains 66 combinations:
      - 5 numbers (1 -> 50) that remain the same for all the grids of the multigrid
      - All the possible combinations of 2 stars (1 -> 12). For each grid of the multigrid at least one of the stars are different (12 choose 2 == 66)
- You can choose the numbers by yourself or generate them randomly with "Flash" this works for both single-chance and multi-chance // not yet implemented

# How is the winner picked?

- When the right time comes to pick a winner, if the pot is >= 17K ether, we check if someone has won the jackpot.
- If there is no winner, the pot is added to the pot of the next lottery.
- This process continues untill we reach 250K ether(the ceiling)
- If we reach 250K ether and there is still no winner, The draw happens 5 more times
- If after the 5 draws there are still no winner, the reward is split between the closest to a win.

# What do we need?

- A lottery contract
- Participants(mapping(address => struct))
- bool to indicate whether the participant generates the numbers randomly(flash = true) or chooses them (flash = false) (variable in a function)
- struct {
  numbers (list of list)
  stars (list of list)
  simple/multichance(enum)
  }
- enum for the state of the lottery
