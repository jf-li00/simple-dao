module mydao::DAO {
    use sui::table::{Table,Self};
    use sui::package::Self;
    use sui::coin::{Self,Coin};
    use sui::event::{Self};
    use sui::balance::{Self, Balance};
    use sui::clock::{Clock, timestamp_ms};
    use mydao::gvc::{GVC};

    // ----------ERROR-----------
    // Duplicate voting
    const E_DUPLICATE_VOTE: u64 = 0;
    // The vote is not enabled for the proposal
    const E_INSUFFICIENT_VOTES: u64 = 1;
    // The proposal voting has not started yet
    const E_VOTING_NOT_STARTED: u64 = 2;
    // The proposal voting has ended
    const E_VOTING_ENDED: u64 = 3;
    // The proposal voting not ended and cannot be executed.
    const E_VOTING_NOT_ENDED: u64 = 4;
    // Match Vote and Proposal
    const EVoteAndProposalIdMismatch: u64 = 5;

    //* ----------Data structures----------
    public struct DAO has drop {}
    
    public struct Proposal has key, store {
        id: UID,
        description: vector<u8>,
        votes_for: u64,
        votes_against: u64,
        // Minimum number of votes required for a proposal to be approved and executed.
        // This includes both 'for' and 'against' votes within a closed interval.
        minimal_votes_required: u64,
        voted:Table<address,bool>,
        // The time when the voting starts and ends, in milliseconds seconds since the Unix epoch
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

    // allow list and deny list for proposals, `true` measn allowed, `false`
    // means denied, and `None` means don't care 
    public struct SepcialList has key, store{
        id : UID,
        list :Table<address,bool>,
    }


    //* ----------Events----------
    // Event to record proposal creation
    public struct ProposalCreatedEvent has copy, drop{
        proposal_id: ID,
        description: vector<u8>,
        minimal_votes_required: u64,
        voting_start: u64,
        voting_end: u64,
    }

    // Event to record voting
    public struct VoteCastEvent has copy, drop{
        proposal_id: ID,
        voter: address,
        decision: bool,
        power_: u64,
    }

    // Event to record proposal execution
    public struct ProposalExecutedEvent has copy, drop{
        proposal_id: ID,
    }

    fun init(otw:DAO, ctx: &mut TxContext) {
        package::claim_and_keep(otw,ctx);
        let special_list = SepcialList{
            id: object::new(ctx),
            list: table::new(ctx),
        };
        
        // Transfer the special list resource to the current module
        transfer::public_transfer(special_list, @mydao);
    }

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

    public fun cast_vote(dao_id_:ID, coin: Coin<GVC>, decision_: bool, ctx: &mut TxContext) : Vote {
        let mut vote = Vote {
            id: object::new(ctx),
            dao_id: dao_id_,
            balance:balance::zero(),
            voting_power: 0,
            decision: decision_,
        };
        let balance_ = coin::into_balance(coin);
        let power_ = balance::value(&balance_);
        balance::join(&mut vote.balance, balance_);
        vote.voting_power = vote.voting_power + power_;
        vote 
    }

    public fun vote(
        proposal: &mut Proposal,
        vote:Vote,
        c: &Clock,
        decision: bool, 
        ctx: &mut TxContext
    ) : Coin<GVC> {
        assert!(timestamp_ms(c) < proposal.voting_end, E_VOTING_ENDED);
        assert!(vote.dao_id == object::id(proposal), EVoteAndProposalIdMismatch);
        let sender = tx_context::sender(ctx);
        // Allow only one vote per proposal for an address. 
        assert!(!proposal.voted.contains(sender), E_DUPLICATE_VOTE);
        // Ensure the time epoch is within the voting period
        let time_now = tx_context::epoch_timestamp_ms(ctx);
        assure_time_in_voting_period(proposal, time_now);
        // Increase the vote count accordingly
        let power_ = vote.voting_power;
        if (decision) {
            proposal.votes_for = proposal.votes_for + power_;
        } else {
            proposal.votes_against = proposal.votes_against + power_;
        };
        let coin = destroy_vote(vote, ctx);
        // Record the vote
        event::emit(VoteCastEvent {
            proposal_id: object::uid_to_inner(&proposal.id),
            voter: sender,
            decision,
            power_,
        });
        coin
    }

    fun destroy_vote(vote: Vote, ctx: &mut TxContext) : Coin<GVC> {
        let Vote {
            id,
            dao_id: _,
            balance,
            voting_power: _,
            decision: _,
        } = vote;

        object::delete(id);
        let coin_ = coin::from_balance(balance, ctx);
        coin_
    }

    public fun execute_proposal(proposal: &mut Proposal, c:&Clock) {
        // The proposal can be executed only if the minimal amount of votes is reached
        assert!(total_votes(proposal) >= proposal.minimal_votes_required, E_INSUFFICIENT_VOTES);
        // Ensure the time epoch is within the voting period
        let time_now = timestamp_ms(c);
        assert!(time_now > proposal.voting_end, E_VOTING_NOT_ENDED);

        proposal.executed = true;
        event::emit(ProposalExecutedEvent {
            proposal_id: object::uid_to_inner(&proposal.id),
        });
    }

    public fun total_votes(proposal: &Proposal) :u64 {
        return (proposal.votes_for + proposal.votes_against)
    }

    fun assure_time_in_voting_period(proposal: &Proposal, time: u64) {
        assert!(time >= proposal.voting_start, E_VOTING_NOT_STARTED);
        assert!(time <= proposal.voting_end, E_VOTING_ENDED);
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        let dao = DAO{};
        init(dao,ctx);
    }
}
