module mydao::DAO {
    use sui::table::{Table, Self};
    use sui::package::Self;
    use sui::coin::{Self, Coin};
    use sui::event::{Self};
    use sui::balance::{Self, Balance};
    use sui::clock::{Clock, timestamp_ms};
    use mydao::gvc::{GVC};

    // Error codes
    const E_DUPLICATE_VOTE: u64 = 0;
    const E_INSUFFICIENT_VOTES: u64 = 1;
    const E_VOTING_NOT_STARTED: u64 = 2;
    const E_VOTING_ENDED: u64 = 3;
    const EVoteAndProposalIdMismatch: u64 = 4;

    // Data structures
    public struct DAO has drop {}
    
    public struct Proposal has key, store {
        id: UID,
        description: vector<u8>,
        votes_for: u64,
        votes_against: u64,
        minimal_votes_required: u64,
        voted: Table<address, bool>,
        voting_start: u64,
        voting_end: u64,
        executed: bool,
    }

    public struct Vote has key, store {
        id: UID,
        dao_id: ID,
        balance: Balance<GVC>,
        voting_power: u64,
        decision: bool,
    }

    public struct SpecialList has key, store {
        id: UID,
        list: Table<address, bool>,
    }

    // Events
    public struct ProposalCreatedEvent has copy, drop {
        proposal_id: ID,
        description: vector<u8>,
        minimal_votes_required: u64,
        voting_start: u64,
        voting_end: u64,
    }

    public struct VoteCastEvent has copy, drop {
        proposal_id: ID,
        voter: address,
        decision: bool,
        power_: u64,
    }

    public struct ProposalExecutedEvent has copy, drop {
        proposal_id: ID,
    }

    // Initialization function
    fun init(otw: DAO, ctx: &mut TxContext) {
        package::claim_and_keep(otw, ctx);
        let special_list = SpecialList {
            id: object::new(ctx),
            list: table::new(ctx),
        };
        
        // Transfer the special list resource to the current module
        transfer::public_transfer(special_list, @mydao);
    }

    // Function to create a proposal
    public fun create_proposal(
        ctx: &mut TxContext,
        c: &Clock, 
        description: vector<u8>,
        minimal_votes_required: u64, 
        voting_start: u64, 
        voting_end: u64
    ) {
        let proposal = Proposal {
            id: object::new(ctx),
            description,
            votes_for: 0,
            votes_against: 0,
            minimal_votes_required,
            voted: table::new(ctx),
            executed: false,
            voting_start: timestamp_ms(c),
            voting_end,
        };

        event::emit(ProposalCreatedEvent {
            proposal_id: object::uid_to_inner(&proposal.id),
            description,
            minimal_votes_required,
            voting_start,
            voting_end,
        });

        transfer::share_object(proposal);
    }

    // Function to cast a vote
    public fun cast_vote(dao_id_: ID, coin: Coin<GVC>, decision_: bool, ctx: &mut TxContext) : Vote {
        let mut vote = Vote {
            id: object::new(ctx),
            dao_id: dao_id_,
            balance: balance::zero(),
            voting_power: 0,
            decision: decision_,
        };
        let balance_ = coin::into_balance(coin);
        let power_ = balance::value(&balance_);
        balance::join(&mut vote.balance, balance_);
        vote.voting_power = power_;
        vote 
    }

    // Function to vote on a proposal
    public fun vote(
        proposal: &mut Proposal,
        vote: Vote,
        c: &Clock,
        decision: bool, 
        ctx: &mut TxContext
    ) : Coin<GVC> {
        let time_now = timestamp_ms(c);
        assure_time_in_voting_period(proposal, time_now);

        let sender = tx_context::sender(ctx);
        assert!(!proposal.voted.contains(sender), E_DUPLICATE_VOTE);

        if decision {
            proposal.votes_for += vote.voting_power;
        } else {
            proposal.votes_against += vote.voting_power;
        };

        proposal.voted.insert(sender, true);

        let coin = destroy_vote(vote, ctx);

        event::emit(VoteCastEvent {
            proposal_id: object::uid_to_inner(&proposal.id),
            voter: sender,
            decision,
            power_: vote.voting_power,
        });
        coin
    }

    // Function to destroy a vote
    fun destroy_vote(vote: Vote, ctx: &mut TxContext) : Coin<GVC> {
        let Vote {
            id,
            balance,
            ..
        } = vote;

        object::delete(id);
        coin::from_balance(balance, ctx)
    }

    // Function to execute a proposal
    public fun execute_proposal(proposal: &mut Proposal, c:&Clock) {
        assert!(total_votes(proposal) >= proposal.minimal_votes_required, E_INSUFFICIENT_VOTES);
        assert!(timestamp_ms(c) > proposal.voting_end, E_VOTING_NOT_ENDED);

        proposal.executed = true;
        event::emit(ProposalExecutedEvent {
            proposal_id: object::uid_to_inner(&proposal.id),
        });
    }

    // Function to get total votes on a proposal
    public fun total_votes(proposal: &Proposal) : u64 {
        return proposal.votes_for + proposal.votes_against;
    }

    // Function to ensure the current time is within the voting period
    fun assure_time_in_voting_period(proposal: &Proposal, time: u64) {
        assert!(time >= proposal.voting_start, E_VOTING_NOT_STARTED);
        assert!(time <= proposal.voting_end, E_VOTING_ENDED);
    }

    // Test function
    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        let dao = DAO{};
        init(dao, ctx);
    }
}
