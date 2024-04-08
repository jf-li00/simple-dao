## Simple DAO
> A quite simple implementaion of DAO in sui MOVE

- `sui version`: 1.22
- `network`: testnet
- `move version` 2024 alpha

## build
```sh
sui move build
```

## test

```sh
sui move test
```


## Documentation
This is a DAO based on a certain kind of `Governance Coin` to publish, vote for and finally execute the `Proposal`s.   

### Governance Coin
Based on the standard `Coin` library in `sui`. It is used to vote for proposals, and one coin stands for one vote.
The coin was first created with a certain amout and could be minted by the TreasuryCap owner.

### Proposal
The `Proposal`s are defined with a `start_time` and an `end_time` to indicate the  voting time interval. 
Besides, `Proposal`s also have a `minimal votes required` limit to indicate the minimal votes for execution(both for and against would count)

### Voting
When voting starts, anyone holding the `Governance Coin` could vote for/against the proposal and the coin will **NOT** be consumed.

Each address could vote only once for each proposal.

### Proposal Execution
When the voting period ends, any one could invoke the `execute_proposal` function to execute the proposal.


## Code Structure
`Governance Coin` and `MyDao` are separated into two move files

## Events
Proposal creation, voting, proposal execution will be logged as events.