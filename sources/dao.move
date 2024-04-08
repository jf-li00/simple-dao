module mydao::DAO {
    use sui::table::{Table,Self};
    use sui::package::Self;
    use sui::coin::{Self,Coin};
    use sui::event::{Self};
    use mydao::GovernanceCoin::{GOVERNANCECOIN};

    // Error Codes
    const INSUFFICIENT_BALANCE: u64 = 102;
    const DUPLICATE_VOTE: u64 = 103;
    const INSUFFICIENT_VOTES: u64 = 104;
    const VOTING_NOT_STARTED: u64 = 105;
    const VOTING_ENDED: u64 = 106;
    const VOTING_NOT_ENDED: u64 = 107;

    // Data Structures
    public struct DAO has drop{}

    public struct Proposal has key, store {
        id: UID,
        description: vector<u8>,
        votes_for: u64,
        votes_against: u64,
        minimal_votes_required: u64,
        voted: Table<address,bool>,
        voting_start: u64,
        voting_end: u64,
        executed: bool,
    }

    public struct SepcialList has key, store{
        id : UID,
        list : Table<address,bool>,
    }

    // Events
    public struct ProposalCreatedEvent has copy, drop{
        proposal_id: ID,
        description: vector<u8>,
        minimal_votes_required: u64,
        voting_start: u64,
        voting_end: u64,
    }

    public struct VoteCastEvent has copy, drop{
        proposal_id: ID,
        voter: address,
        vote: bool,
        amount: u64,
    }

    public struct ProposalExecutedEvent has copy, drop{
        proposal_id: ID,
    }

    fun init(otw:DAO, ctx: &mut sui::tx_context::TxContext) {
        package::claim_and_keep(otw,ctx);
        let special_list = SepcialList{
            id: object::new(ctx),
            list: table::new(ctx),
        };
        transfer::public_transfer(special_list, @mydao);
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        let dao = DAO{};
        init(dao,ctx);
    }

    public fun create_proposal(ctx: &mut TxContext, description: vector<u8>,
        minimal_votes_required: u64, voting_start: u64, voting_end: u64) {
        assert!(voting_start < voting_end, VOTING_NOT_STARTED);
        let proposal = Proposal {
            id: object::new(ctx),
            description,
            votes_for: 0,
            votes_against: 0,
            minimal_votes_required,
            voted: table::new(ctx),
            executed: false,
            voting_start,
            voting_end,
        };

        let proposal_creation_record = ProposalCreatedEvent {
            proposal_id: object::uid_to_inner(&proposal.id),
            description,
            minimal_votes_required,
            voting_start,
            voting_end,
        };
        event::emit(proposal_creation_record);

        transfer::share_object(proposal);
    }

    public fun vote(ctx: &mut TxContext, proposal: &mut Proposal, vote: bool, amount:
    u64,governance_coin : &Coin<GOVERNANCECOIN>) {
        let time_now = tx_context::epoch_timestamp_ms(ctx);
        ensure_time_in_voting_period(proposal, time_now);

        let sender = tx_context::sender(ctx);
        let balance = coin::value(governance_coin);
        assert!(balance >= amount, INSUFFICIENT_BALANCE);
        
        // Ensure the user hasn't voted before
        assert!(!proposal.voted.contains(sender), DUPLICATE_VOTE);


        if (vote) {
            proposal.votes_for = proposal.votes_for+amount;
        } else {
            proposal.votes_against = proposal.votes_against+amount;
        };

        proposal.voted.add(sender,vote);

        let vote_record = VoteCastEvent {
            proposal_id: object::uid_to_inner(&proposal.id),
            voter: sender,
            vote,
            amount,
        };
        event::emit(vote_record);
    }

    public fun execute_proposal(ctx: &mut TxContext, proposal: &mut Proposal) {
        assert!(total_votes(proposal)>= proposal.minimal_votes_required,
        INSUFFICIENT_VOTES);
        let time_now = tx_context::epoch_timestamp_ms(ctx);
        assert!(time_now > proposal.voting_end, VOTING_NOT_ENDED);

        proposal.executed = true;
        let proposal_execution_record = ProposalExecutedEvent {
            proposal_id: object::uid_to_inner(&proposal.id),
        };
        event::emit(proposal_execution_record);
    }

    public fun total_votes(proposal: &Proposal) :u64 {
        return (proposal.votes_for + proposal.votes_against)
    }

    fun ensure_time_in_voting_period(proposal: &Proposal, time: u64) {
        assert!(time >= proposal.voting_start, VOTING_NOT_STARTED);
        assert!(time <= proposal.voting_end, VOTING_ENDED);
    }

    #[test_only] use std::debug;
    #[test_only] use sui::test_scenario;
    #[test_only] use mydao::GovernanceCoin;
    #[test_only] use sui::coin::{TreasuryCap};

    #[test_only] const VOTING_INTERVAL: u64 = 100;
    #[test]
    fun test_dao() {
        let (alice,bob,carol) = (@0x10,@0x20,@0x30);
        let mut scenario = test_scenario::begin(alice);

        // First transaction, init the DAO and gov coin module.
        {
            scenario.next_tx(bob);
            GovernanceCoin::test_init(scenario.ctx());
            test_init(scenario.ctx());
        };

        // Second transaction, mint some coin for carol and create a proposal
        {
            scenario.next_tx(bob);
            let mut treasury_cap:TreasuryCap<GOVERNANCECOIN> =
            test_scenario::take_from_sender(&scenario);
            coin::mint_and_transfer(&mut treasury_cap, 1000, carol,
            scenario.ctx());
            scenario.return_to_sender(treasury_cap);

            let now = tx_context::epoch_timestamp_ms(scenario.ctx());
            create_proposal(scenario.ctx(), b"test proposal", 10, now, now+VOTING_INTERVAL );
        };

        // Third transaction, let carol vote for the proposal.
        {
            scenario.next_tx(carol);

            let coin = scenario.take_from_sender<Coin<GOVERNANCECOIN>>();
            let mut proposal = scenario.take_shared<Proposal>();

            vote(scenario.ctx(), &mut proposal, true, 100, &coin);
            debug::print(&proposal);

            scenario.return_to_sender(coin);
            test_scenario::return_shared(proposal);

        };

        // Edge case, should not fail.
        {
            scenario.later_epoch(VOTING_INTERVAL ,bob);

            let coin = scenario.take_from_sender<Coin<GOVERNANCECOIN>>();
            let mut proposal = scenario.take_shared<Proposal>();

            vote(scenario.ctx(), &mut proposal, true, 10000, &coin);
            debug::print(&proposal);

            scenario.return_to_sender(coin);
            test_scenario::return_shared(proposal);

        };

        // Execute the proposal
        {
            scenario.later_epoch(1,bob);
            let mut proposal = scenario.take_shared<Proposal>();
            execute_proposal(scenario.ctx(), &mut proposal);
            debug::print(&proposal);
            test_scenario::return_shared(proposal);
        };

        scenario.end();
    }
}
