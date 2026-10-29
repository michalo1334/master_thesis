--
-- PostgreSQL database dump
--

\restrict Ha02MybnoGsJqJdipAmbFcqiZoOGzFGuFSebLXgGen9QD6G8mBEchnQddBA86cm

-- Dumped from database version 18.6 (Debian 18.6-1.pgdg13+2)
-- Dumped by pg_dump version 18.3 (Ubuntu 18.3-1.pgdg24.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: oban_job_state; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.oban_job_state AS ENUM (
    'available',
    'suspended',
    'scheduled',
    'executing',
    'retryable',
    'completed',
    'discarded',
    'cancelled'
);


--
-- Name: prevent_evaluation_study_result_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_evaluation_study_result_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'evaluation study results are immutable';
END;
$$;


--
-- Name: prevent_graph_snapshot_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_graph_snapshot_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'graph snapshots are immutable';
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: edges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.edges (
    id uuid NOT NULL,
    graph_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: evaluation_evidence_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evaluation_evidence_snapshots (
    id uuid NOT NULL,
    study_revision_id uuid NOT NULL,
    phase character varying(255) NOT NULL,
    schema_version integer NOT NULL,
    family_id character varying(255) NOT NULL,
    payload jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT evaluation_evidence_snapshots_phase_valid CHECK (((phase)::text = ANY ((ARRAY['pilot'::character varying, 'final'::character varying])::text[]))),
    CONSTRAINT evaluation_evidence_snapshots_schema_version_valid CHECK ((schema_version = 1))
);


--
-- Name: evaluation_study_collection_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evaluation_study_collection_items (
    id uuid NOT NULL,
    study_phase_id uuid NOT NULL,
    replica_position integer NOT NULL,
    item_position integer NOT NULL,
    optimization_run_id uuid,
    experiment_id uuid,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT study_collection_items_replica_position_check CHECK (((replica_position >= '-1'::integer) AND (replica_position <= 4)))
);


--
-- Name: evaluation_study_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evaluation_study_executions (
    id uuid NOT NULL,
    study_revision_id uuid NOT NULL,
    state character varying(255) NOT NULL,
    error jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    pilot_outcome jsonb,
    selected_candidate_id character varying(255),
    selected_plan_count_per_side integer,
    selected_attacks_per_plan integer,
    pilot_override boolean,
    CONSTRAINT evaluation_study_executions_final_selection_all_or_none CHECK ((((selected_candidate_id IS NULL) AND (selected_plan_count_per_side IS NULL) AND (selected_attacks_per_plan IS NULL) AND (pilot_override IS NULL)) OR ((selected_candidate_id IS NOT NULL) AND (selected_plan_count_per_side IS NOT NULL) AND (selected_attacks_per_plan IS NOT NULL) AND (pilot_override IS NOT NULL)))),
    CONSTRAINT evaluation_study_executions_selected_attacks_per_plan_positive CHECK (((selected_attacks_per_plan IS NULL) OR (selected_attacks_per_plan > 0))),
    CONSTRAINT evaluation_study_executions_selected_candidate_id_valid CHECK (((selected_candidate_id IS NULL) OR ((char_length((selected_candidate_id)::text) >= 1) AND (char_length((selected_candidate_id)::text) <= 128)))),
    CONSTRAINT evaluation_study_executions_selected_plan_count_positive CHECK (((selected_plan_count_per_side IS NULL) OR (selected_plan_count_per_side > 0))),
    CONSTRAINT evaluation_study_executions_state_valid CHECK (((state)::text = ANY ((ARRAY['collecting_pilot'::character varying, 'analyzing_pilot'::character varying, 'awaiting_final'::character varying, 'collecting_final'::character varying, 'analyzing_final'::character varying, 'succeeded'::character varying, 'failed'::character varying, 'cancelled'::character varying])::text[])))
);


--
-- Name: evaluation_study_phase_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evaluation_study_phase_runs (
    id uuid NOT NULL,
    study_phase_id uuid NOT NULL,
    tier character varying(255) NOT NULL,
    tier_position integer NOT NULL,
    gust_run_id integer,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT study_phase_runs_tier_position_check CHECK ((tier_position >= 0))
);


--
-- Name: evaluation_study_phases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evaluation_study_phases (
    id uuid NOT NULL,
    execution_id uuid NOT NULL,
    phase character varying(255) NOT NULL,
    gust_run_id bigint,
    snapshot_id uuid,
    result_ref jsonb,
    error jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT evaluation_study_phases_phase_valid CHECK (((phase)::text = ANY ((ARRAY['pilot_collection'::character varying, 'pilot_analysis'::character varying, 'final_collection'::character varying, 'final_analysis'::character varying])::text[])))
);


--
-- Name: evaluation_study_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evaluation_study_results (
    id uuid NOT NULL,
    execution_id uuid NOT NULL,
    schema_version integer NOT NULL,
    data jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT evaluation_study_results_schema_version_valid CHECK ((schema_version = 1))
);


--
-- Name: evaluation_study_revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evaluation_study_revisions (
    id uuid NOT NULL,
    study_id character varying(255) NOT NULL,
    revision integer NOT NULL,
    schema_version integer NOT NULL,
    definition jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: experiments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.experiments (
    id uuid CONSTRAINT multi_states_id_not_null NOT NULL,
    master_seed bigint CONSTRAINT multi_states_seed_not_null NOT NULL,
    iteration_count integer CONSTRAINT multi_states_iteration_count_not_null NOT NULL,
    inserted_at timestamp(0) without time zone CONSTRAINT multi_states_inserted_at_not_null NOT NULL,
    updated_at timestamp(0) without time zone CONSTRAINT multi_states_updated_at_not_null NOT NULL,
    runtime_ms integer DEFAULT 0 CONSTRAINT multi_states_runtime_ms_not_null NOT NULL,
    max_attempts integer DEFAULT 1 NOT NULL,
    total_trials integer DEFAULT 0 NOT NULL,
    completed_trials integer DEFAULT 0 NOT NULL,
    status character varying(255) DEFAULT 'running'::character varying NOT NULL,
    initial_foothold_node_id uuid,
    graph_revision_id uuid NOT NULL,
    CONSTRAINT experiments_completed_trials_non_negative CHECK (((completed_trials >= 0) AND (completed_trials <= total_trials))),
    CONSTRAINT experiments_iteration_count_positive CHECK ((iteration_count > 0)),
    CONSTRAINT experiments_master_seed_non_negative CHECK ((master_seed >= 0)),
    CONSTRAINT experiments_max_attempts_positive CHECK ((max_attempts > 0)),
    CONSTRAINT experiments_status_valid CHECK (((status)::text = ANY ((ARRAY['running'::character varying, 'failed'::character varying, 'completed'::character varying, 'cancelled'::character varying])::text[]))),
    CONSTRAINT experiments_total_trials_positive CHECK ((total_trials > 0))
);


--
-- Name: graph_folders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.graph_folders (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: graph_revision_edges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.graph_revision_edges (
    graph_id uuid NOT NULL,
    graph_revision_id uuid NOT NULL,
    edge_id uuid NOT NULL,
    from_id uuid NOT NULL,
    to_id uuid NOT NULL,
    type character varying(255) NOT NULL,
    data jsonb
);


--
-- Name: graph_revision_favorites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.graph_revision_favorites (
    graph_revision_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: graph_revision_nodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.graph_revision_nodes (
    graph_id uuid NOT NULL,
    graph_revision_id uuid NOT NULL,
    node_id uuid NOT NULL,
    type character varying(255) NOT NULL,
    data jsonb,
    view_data jsonb NOT NULL
);


--
-- Name: graph_revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.graph_revisions (
    id uuid NOT NULL,
    graph_id uuid NOT NULL,
    parent_revision_id uuid,
    number integer NOT NULL,
    kind character varying(255) NOT NULL,
    title character varying(255) NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    CONSTRAINT graph_revisions_kind_valid CHECK (((kind)::text = ANY ((ARRAY['initial'::character varying, 'edit'::character varying, 'optimization'::character varying])::text[]))),
    CONSTRAINT graph_revisions_number_positive CHECK ((number > 0)),
    CONSTRAINT graph_revisions_parent_required CHECK (((((kind)::text = 'initial'::text) AND (parent_revision_id IS NULL)) OR (((kind)::text = ANY ((ARRAY['edit'::character varying, 'optimization'::character varying])::text[])) AND (parent_revision_id IS NOT NULL))))
);


--
-- Name: graphs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.graphs (
    id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    folder_id uuid
);


--
-- Name: iteration_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.iteration_steps (
    id uuid NOT NULL,
    run_id uuid CONSTRAINT iteration_steps_simulation_id_not_null NOT NULL,
    index integer NOT NULL,
    attempted_action jsonb,
    success boolean NOT NULL,
    attacker_state jsonb NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    CONSTRAINT iteration_steps_index_positive CHECK ((index > 0))
);


--
-- Name: nodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.nodes (
    id uuid NOT NULL,
    graph_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: oban_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oban_jobs (
    id bigint NOT NULL,
    state public.oban_job_state DEFAULT 'available'::public.oban_job_state NOT NULL,
    queue text DEFAULT 'default'::text NOT NULL,
    worker text NOT NULL,
    args jsonb DEFAULT '{}'::jsonb NOT NULL,
    errors jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
    attempt integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 20 NOT NULL,
    inserted_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    scheduled_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    attempted_at timestamp without time zone,
    completed_at timestamp without time zone,
    attempted_by text[],
    discarded_at timestamp without time zone,
    priority integer DEFAULT 0 NOT NULL,
    tags text[] DEFAULT ARRAY[]::text[],
    meta jsonb DEFAULT '{}'::jsonb,
    cancelled_at timestamp without time zone,
    CONSTRAINT attempt_range CHECK (((attempt >= 0) AND (attempt <= max_attempts))),
    CONSTRAINT positive_max_attempts CHECK ((max_attempts > 0)),
    CONSTRAINT queue_length CHECK (((char_length(queue) > 0) AND (char_length(queue) < 128))),
    CONSTRAINT worker_length CHECK (((char_length(worker) > 0) AND (char_length(worker) < 128)))
);


--
-- Name: TABLE oban_jobs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.oban_jobs IS '14';


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oban_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oban_jobs_id_seq OWNED BY public.oban_jobs.id;


--
-- Name: oban_peers; Type: TABLE; Schema: public; Owner: -
--

CREATE UNLOGGED TABLE public.oban_peers (
    name text NOT NULL,
    node text NOT NULL,
    started_at timestamp without time zone NOT NULL,
    expires_at timestamp without time zone NOT NULL
);


--
-- Name: optimization_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.optimization_actions (
    id uuid NOT NULL,
    optimization_run_id uuid NOT NULL,
    "position" integer NOT NULL,
    action_type character varying(255) NOT NULL,
    target_id uuid NOT NULL,
    cost integer NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    CONSTRAINT optimization_actions_cost_non_negative CHECK ((cost >= 0)),
    CONSTRAINT optimization_actions_position_positive CHECK (("position" > 0))
);


--
-- Name: optimization_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.optimization_runs (
    id uuid NOT NULL,
    graph_revision_id uuid NOT NULL,
    output_graph_revision_id uuid,
    strategy character varying(255) NOT NULL,
    requested_budget integer NOT NULL,
    used_budget integer DEFAULT 0 NOT NULL,
    runtime_ms integer DEFAULT 0 NOT NULL,
    status character varying(255) DEFAULT 'running'::character varying NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    seed bigint,
    simulation_config jsonb,
    CONSTRAINT optimization_runs_completed_output_revision CHECK ((((status)::text <> 'completed'::text) OR (output_graph_revision_id IS NOT NULL))),
    CONSTRAINT optimization_runs_requested_budget_positive CHECK ((requested_budget > 0)),
    CONSTRAINT optimization_runs_runtime_ms_non_negative CHECK ((runtime_ms >= 0)),
    CONSTRAINT optimization_runs_status_valid CHECK (((status)::text = ANY ((ARRAY['running'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying])::text[]))),
    CONSTRAINT optimization_runs_used_budget_non_negative CHECK ((used_budget >= 0))
);


--
-- Name: simulation_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.simulation_runs (
    id uuid CONSTRAINT simulations_id_not_null NOT NULL,
    seed bigint CONSTRAINT simulations_initial_seed_not_null NOT NULL,
    initial_attacker_state jsonb CONSTRAINT simulations_initial_attacker_state_not_null NOT NULL,
    inserted_at timestamp(0) without time zone CONSTRAINT simulations_inserted_at_not_null NOT NULL,
    updated_at timestamp(0) without time zone CONSTRAINT simulations_updated_at_not_null NOT NULL,
    experiment_id uuid,
    trial_index integer DEFAULT 0 NOT NULL,
    graph_revision_id uuid NOT NULL,
    runtime_us bigint,
    CONSTRAINT simulation_runs_runtime_us_non_negative CHECK (((runtime_us IS NULL) OR (runtime_us >= 0))),
    CONSTRAINT simulation_runs_seed_non_negative CHECK ((seed >= 0))
);


--
-- Name: oban_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_jobs ALTER COLUMN id SET DEFAULT nextval('public.oban_jobs_id_seq'::regclass);


--
-- Name: edges edges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.edges
    ADD CONSTRAINT edges_pkey PRIMARY KEY (id);


--
-- Name: evaluation_evidence_snapshots evaluation_evidence_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_evidence_snapshots
    ADD CONSTRAINT evaluation_evidence_snapshots_pkey PRIMARY KEY (id);


--
-- Name: evaluation_study_collection_items evaluation_study_collection_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_study_collection_items
    ADD CONSTRAINT evaluation_study_collection_items_pkey PRIMARY KEY (id);


--
-- Name: evaluation_study_executions evaluation_study_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_study_executions
    ADD CONSTRAINT evaluation_study_executions_pkey PRIMARY KEY (id);


--
-- Name: evaluation_study_phase_runs evaluation_study_phase_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_study_phase_runs
    ADD CONSTRAINT evaluation_study_phase_runs_pkey PRIMARY KEY (id);


--
-- Name: evaluation_study_phases evaluation_study_phases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_study_phases
    ADD CONSTRAINT evaluation_study_phases_pkey PRIMARY KEY (id);


--
-- Name: evaluation_study_results evaluation_study_results_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_study_results
    ADD CONSTRAINT evaluation_study_results_pkey PRIMARY KEY (id);


--
-- Name: evaluation_study_revisions evaluation_study_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_study_revisions
    ADD CONSTRAINT evaluation_study_revisions_pkey PRIMARY KEY (id);


--
-- Name: graph_folders graph_folders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_folders
    ADD CONSTRAINT graph_folders_pkey PRIMARY KEY (id);


--
-- Name: graph_revision_edges graph_revision_edges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_revision_edges
    ADD CONSTRAINT graph_revision_edges_pkey PRIMARY KEY (graph_revision_id, edge_id);


--
-- Name: graph_revision_favorites graph_revision_favorites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_revision_favorites
    ADD CONSTRAINT graph_revision_favorites_pkey PRIMARY KEY (graph_revision_id);


--
-- Name: graph_revision_nodes graph_revision_nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_revision_nodes
    ADD CONSTRAINT graph_revision_nodes_pkey PRIMARY KEY (graph_revision_id, node_id);


--
-- Name: graph_revisions graph_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_revisions
    ADD CONSTRAINT graph_revisions_pkey PRIMARY KEY (id);


--
-- Name: graphs graphs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graphs
    ADD CONSTRAINT graphs_pkey PRIMARY KEY (id);


--
-- Name: iteration_steps iteration_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.iteration_steps
    ADD CONSTRAINT iteration_steps_pkey PRIMARY KEY (id);


--
-- Name: experiments multi_states_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.experiments
    ADD CONSTRAINT multi_states_pkey PRIMARY KEY (id);


--
-- Name: nodes nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nodes
    ADD CONSTRAINT nodes_pkey PRIMARY KEY (id);


--
-- Name: oban_jobs non_negative_priority; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.oban_jobs
    ADD CONSTRAINT non_negative_priority CHECK ((priority >= 0)) NOT VALID;


--
-- Name: oban_jobs oban_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_jobs
    ADD CONSTRAINT oban_jobs_pkey PRIMARY KEY (id);


--
-- Name: oban_peers oban_peers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_peers
    ADD CONSTRAINT oban_peers_pkey PRIMARY KEY (name);


--
-- Name: optimization_actions optimization_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.optimization_actions
    ADD CONSTRAINT optimization_actions_pkey PRIMARY KEY (id);


--
-- Name: optimization_runs optimization_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.optimization_runs
    ADD CONSTRAINT optimization_runs_pkey PRIMARY KEY (id);


--
-- Name: simulation_runs simulations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.simulation_runs
    ADD CONSTRAINT simulations_pkey PRIMARY KEY (id);


--
-- Name: edges_graph_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX edges_graph_id_index ON public.edges USING btree (graph_id);


--
-- Name: edges_id_graph_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX edges_id_graph_id_index ON public.edges USING btree (id, graph_id);


--
-- Name: evaluation_evidence_snapshots_study_revision_id_family_id_phase; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX evaluation_evidence_snapshots_study_revision_id_family_id_phase ON public.evaluation_evidence_snapshots USING btree (study_revision_id, family_id, phase);


--
-- Name: evaluation_study_collection_items_position_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX evaluation_study_collection_items_position_index ON public.evaluation_study_collection_items USING btree (study_phase_id, replica_position, item_position);


--
-- Name: evaluation_study_phase_runs_gust_run_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX evaluation_study_phase_runs_gust_run_id_index ON public.evaluation_study_phase_runs USING btree (gust_run_id) WHERE (gust_run_id IS NOT NULL);


--
-- Name: evaluation_study_phase_runs_study_phase_id_tier_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX evaluation_study_phase_runs_study_phase_id_tier_index ON public.evaluation_study_phase_runs USING btree (study_phase_id, tier);


--
-- Name: evaluation_study_phase_runs_study_phase_id_tier_position_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX evaluation_study_phase_runs_study_phase_id_tier_position_index ON public.evaluation_study_phase_runs USING btree (study_phase_id, tier_position);


--
-- Name: evaluation_study_phases_execution_id_phase_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX evaluation_study_phases_execution_id_phase_index ON public.evaluation_study_phases USING btree (execution_id, phase);


--
-- Name: evaluation_study_results_execution_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX evaluation_study_results_execution_id_index ON public.evaluation_study_results USING btree (execution_id);


--
-- Name: evaluation_study_revisions_study_id_revision_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX evaluation_study_revisions_study_id_revision_index ON public.evaluation_study_revisions USING btree (study_id, revision);


--
-- Name: experiments_graph_revision_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX experiments_graph_revision_id_index ON public.experiments USING btree (graph_revision_id);


--
-- Name: experiments_id_graph_revision_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX experiments_id_graph_revision_id_index ON public.experiments USING btree (id, graph_revision_id);


--
-- Name: graph_revision_edges_edge_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX graph_revision_edges_edge_id_index ON public.graph_revision_edges USING btree (edge_id);


--
-- Name: graph_revision_nodes_node_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX graph_revision_nodes_node_id_index ON public.graph_revision_nodes USING btree (node_id);


--
-- Name: graph_revisions_graph_id_number_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX graph_revisions_graph_id_number_index ON public.graph_revisions USING btree (graph_id, number);


--
-- Name: graph_revisions_id_graph_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX graph_revisions_id_graph_id_index ON public.graph_revisions USING btree (id, graph_id);


--
-- Name: graph_revisions_parent_revision_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX graph_revisions_parent_revision_id_index ON public.graph_revisions USING btree (parent_revision_id);


--
-- Name: graphs_folder_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX graphs_folder_id_index ON public.graphs USING btree (folder_id);


--
-- Name: iteration_steps_run_id_index_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX iteration_steps_run_id_index_index ON public.iteration_steps USING btree (run_id, index);


--
-- Name: nodes_graph_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX nodes_graph_id_index ON public.nodes USING btree (graph_id);


--
-- Name: nodes_id_graph_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX nodes_id_graph_id_index ON public.nodes USING btree (id, graph_id);


--
-- Name: oban_jobs_args_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_args_index ON public.oban_jobs USING gin (args);


--
-- Name: oban_jobs_meta_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_meta_index ON public.oban_jobs USING gin (meta);


--
-- Name: oban_jobs_state_cancelled_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_state_cancelled_at_index ON public.oban_jobs USING btree (state, cancelled_at);


--
-- Name: oban_jobs_state_discarded_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_state_discarded_at_index ON public.oban_jobs USING btree (state, discarded_at);


--
-- Name: oban_jobs_state_queue_priority_scheduled_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_state_queue_priority_scheduled_at_id_index ON public.oban_jobs USING btree (state, queue, priority, scheduled_at, id);


--
-- Name: optimization_actions_optimization_run_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX optimization_actions_optimization_run_id_index ON public.optimization_actions USING btree (optimization_run_id);


--
-- Name: optimization_actions_optimization_run_id_position_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX optimization_actions_optimization_run_id_position_index ON public.optimization_actions USING btree (optimization_run_id, "position");


--
-- Name: optimization_runs_graph_revision_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX optimization_runs_graph_revision_id_index ON public.optimization_runs USING btree (graph_revision_id);


--
-- Name: simulation_runs_experiment_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX simulation_runs_experiment_id_index ON public.simulation_runs USING btree (experiment_id);


--
-- Name: simulation_runs_experiment_id_trial_index_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX simulation_runs_experiment_id_trial_index_index ON public.simulation_runs USING btree (experiment_id, trial_index);


--
-- Name: simulation_runs_graph_revision_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX simulation_runs_graph_revision_id_index ON public.simulation_runs USING btree (graph_revision_id);


--
-- Name: evaluation_study_results evaluation_study_results_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER evaluation_study_results_immutable BEFORE DELETE OR UPDATE ON public.evaluation_study_results FOR EACH ROW EXECUTE FUNCTION public.prevent_evaluation_study_result_change();


--
-- Name: graph_revision_edges graph_revision_edges_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER graph_revision_edges_immutable BEFORE UPDATE ON public.graph_revision_edges FOR EACH ROW EXECUTE FUNCTION public.prevent_graph_snapshot_update();


--
-- Name: graph_revision_nodes graph_revision_nodes_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER graph_revision_nodes_immutable BEFORE UPDATE ON public.graph_revision_nodes FOR EACH ROW EXECUTE FUNCTION public.prevent_graph_snapshot_update();


--
-- Name: graph_revisions graph_revisions_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER graph_revisions_immutable BEFORE UPDATE ON public.graph_revisions FOR EACH ROW EXECUTE FUNCTION public.prevent_graph_snapshot_update();


--
-- Name: edges edges_graph_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.edges
    ADD CONSTRAINT edges_graph_id_fkey FOREIGN KEY (graph_id) REFERENCES public.graphs(id) ON DELETE CASCADE;


--
-- Name: evaluation_study_collection_items evaluation_study_collection_items_experiment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_study_collection_items
    ADD CONSTRAINT evaluation_study_collection_items_experiment_id_fkey FOREIGN KEY (experiment_id) REFERENCES public.experiments(id) ON DELETE SET NULL;


--
-- Name: evaluation_study_collection_items evaluation_study_collection_items_optimization_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_study_collection_items
    ADD CONSTRAINT evaluation_study_collection_items_optimization_run_id_fkey FOREIGN KEY (optimization_run_id) REFERENCES public.optimization_runs(id) ON DELETE SET NULL;


--
-- Name: evaluation_study_collection_items evaluation_study_collection_items_study_phase_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_study_collection_items
    ADD CONSTRAINT evaluation_study_collection_items_study_phase_id_fkey FOREIGN KEY (study_phase_id) REFERENCES public.evaluation_study_phases(id) ON DELETE CASCADE;


--
-- Name: evaluation_study_executions evaluation_study_executions_study_revision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_study_executions
    ADD CONSTRAINT evaluation_study_executions_study_revision_id_fkey FOREIGN KEY (study_revision_id) REFERENCES public.evaluation_study_revisions(id) ON DELETE RESTRICT;


--
-- Name: evaluation_study_phase_runs evaluation_study_phase_runs_study_phase_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_study_phase_runs
    ADD CONSTRAINT evaluation_study_phase_runs_study_phase_id_fkey FOREIGN KEY (study_phase_id) REFERENCES public.evaluation_study_phases(id) ON DELETE CASCADE;


--
-- Name: evaluation_study_phases evaluation_study_phases_execution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_study_phases
    ADD CONSTRAINT evaluation_study_phases_execution_id_fkey FOREIGN KEY (execution_id) REFERENCES public.evaluation_study_executions(id) ON DELETE RESTRICT;


--
-- Name: evaluation_study_phases evaluation_study_phases_snapshot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_study_phases
    ADD CONSTRAINT evaluation_study_phases_snapshot_id_fkey FOREIGN KEY (snapshot_id) REFERENCES public.evaluation_evidence_snapshots(id) ON DELETE RESTRICT;


--
-- Name: evaluation_study_results evaluation_study_results_execution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_study_results
    ADD CONSTRAINT evaluation_study_results_execution_id_fkey FOREIGN KEY (execution_id) REFERENCES public.evaluation_study_executions(id) ON DELETE RESTRICT;


--
-- Name: experiments experiments_graph_revision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.experiments
    ADD CONSTRAINT experiments_graph_revision_id_fkey FOREIGN KEY (graph_revision_id) REFERENCES public.graph_revisions(id) ON DELETE CASCADE;


--
-- Name: graph_revision_edges graph_revision_edges_edge_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_revision_edges
    ADD CONSTRAINT graph_revision_edges_edge_id_fkey FOREIGN KEY (edge_id, graph_id) REFERENCES public.edges(id, graph_id) ON DELETE RESTRICT;


--
-- Name: graph_revision_edges graph_revision_edges_from_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_revision_edges
    ADD CONSTRAINT graph_revision_edges_from_id_fkey FOREIGN KEY (from_id, graph_id) REFERENCES public.nodes(id, graph_id) ON DELETE RESTRICT;


--
-- Name: graph_revision_edges graph_revision_edges_from_revision_node_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_revision_edges
    ADD CONSTRAINT graph_revision_edges_from_revision_node_fkey FOREIGN KEY (graph_revision_id, from_id) REFERENCES public.graph_revision_nodes(graph_revision_id, node_id) ON DELETE CASCADE;


--
-- Name: graph_revision_edges graph_revision_edges_graph_revision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_revision_edges
    ADD CONSTRAINT graph_revision_edges_graph_revision_id_fkey FOREIGN KEY (graph_revision_id, graph_id) REFERENCES public.graph_revisions(id, graph_id) ON DELETE CASCADE;


--
-- Name: graph_revision_edges graph_revision_edges_to_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_revision_edges
    ADD CONSTRAINT graph_revision_edges_to_id_fkey FOREIGN KEY (to_id, graph_id) REFERENCES public.nodes(id, graph_id) ON DELETE RESTRICT;


--
-- Name: graph_revision_edges graph_revision_edges_to_revision_node_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_revision_edges
    ADD CONSTRAINT graph_revision_edges_to_revision_node_fkey FOREIGN KEY (graph_revision_id, to_id) REFERENCES public.graph_revision_nodes(graph_revision_id, node_id) ON DELETE CASCADE;


--
-- Name: graph_revision_favorites graph_revision_favorites_graph_revision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_revision_favorites
    ADD CONSTRAINT graph_revision_favorites_graph_revision_id_fkey FOREIGN KEY (graph_revision_id) REFERENCES public.graph_revisions(id) ON DELETE CASCADE;


--
-- Name: graph_revision_nodes graph_revision_nodes_graph_revision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_revision_nodes
    ADD CONSTRAINT graph_revision_nodes_graph_revision_id_fkey FOREIGN KEY (graph_revision_id, graph_id) REFERENCES public.graph_revisions(id, graph_id) ON DELETE CASCADE;


--
-- Name: graph_revision_nodes graph_revision_nodes_node_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_revision_nodes
    ADD CONSTRAINT graph_revision_nodes_node_id_fkey FOREIGN KEY (node_id, graph_id) REFERENCES public.nodes(id, graph_id) ON DELETE RESTRICT;


--
-- Name: graph_revisions graph_revisions_graph_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_revisions
    ADD CONSTRAINT graph_revisions_graph_id_fkey FOREIGN KEY (graph_id) REFERENCES public.graphs(id) ON DELETE CASCADE;


--
-- Name: graph_revisions graph_revisions_parent_revision_graph_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graph_revisions
    ADD CONSTRAINT graph_revisions_parent_revision_graph_fkey FOREIGN KEY (parent_revision_id, graph_id) REFERENCES public.graph_revisions(id, graph_id) ON DELETE CASCADE;


--
-- Name: graphs graphs_folder_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.graphs
    ADD CONSTRAINT graphs_folder_id_fkey FOREIGN KEY (folder_id) REFERENCES public.graph_folders(id) ON DELETE SET NULL;


--
-- Name: iteration_steps iteration_steps_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.iteration_steps
    ADD CONSTRAINT iteration_steps_run_id_fkey FOREIGN KEY (run_id) REFERENCES public.simulation_runs(id) ON DELETE CASCADE;


--
-- Name: nodes nodes_graph_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nodes
    ADD CONSTRAINT nodes_graph_id_fkey FOREIGN KEY (graph_id) REFERENCES public.graphs(id) ON DELETE CASCADE;


--
-- Name: optimization_actions optimization_actions_optimization_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.optimization_actions
    ADD CONSTRAINT optimization_actions_optimization_run_id_fkey FOREIGN KEY (optimization_run_id) REFERENCES public.optimization_runs(id) ON DELETE CASCADE;


--
-- Name: optimization_runs optimization_runs_graph_revision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.optimization_runs
    ADD CONSTRAINT optimization_runs_graph_revision_id_fkey FOREIGN KEY (graph_revision_id) REFERENCES public.graph_revisions(id) ON DELETE CASCADE;


--
-- Name: optimization_runs optimization_runs_output_graph_revision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.optimization_runs
    ADD CONSTRAINT optimization_runs_output_graph_revision_id_fkey FOREIGN KEY (output_graph_revision_id) REFERENCES public.graph_revisions(id) ON DELETE CASCADE;


--
-- Name: simulation_runs simulation_runs_experiment_revision_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.simulation_runs
    ADD CONSTRAINT simulation_runs_experiment_revision_fkey FOREIGN KEY (experiment_id, graph_revision_id) REFERENCES public.experiments(id, graph_revision_id) ON DELETE CASCADE;


--
-- Name: simulation_runs simulation_runs_graph_revision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.simulation_runs
    ADD CONSTRAINT simulation_runs_graph_revision_id_fkey FOREIGN KEY (graph_revision_id) REFERENCES public.graph_revisions(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict Ha02MybnoGsJqJdipAmbFcqiZoOGzFGuFSebLXgGen9QD6G8mBEchnQddBA86cm

INSERT INTO public.schema_migrations (version) VALUES (20260710195300);
INSERT INTO public.schema_migrations (version) VALUES (20260710195428);
INSERT INTO public.schema_migrations (version) VALUES (20260710195625);
INSERT INTO public.schema_migrations (version) VALUES (20260717000001);
INSERT INTO public.schema_migrations (version) VALUES (20260717120000);
INSERT INTO public.schema_migrations (version) VALUES (20260717130000);
INSERT INTO public.schema_migrations (version) VALUES (20260718120000);
INSERT INTO public.schema_migrations (version) VALUES (20260719200000);
INSERT INTO public.schema_migrations (version) VALUES (20260719200001);
INSERT INTO public.schema_migrations (version) VALUES (20260719200002);
INSERT INTO public.schema_migrations (version) VALUES (20260719200003);
INSERT INTO public.schema_migrations (version) VALUES (20260719200004);
INSERT INTO public.schema_migrations (version) VALUES (20260723120000);
INSERT INTO public.schema_migrations (version) VALUES (20260726120000);
INSERT INTO public.schema_migrations (version) VALUES (20260726130000);
INSERT INTO public.schema_migrations (version) VALUES (20260728120000);
INSERT INTO public.schema_migrations (version) VALUES (20260729120000);
INSERT INTO public.schema_migrations (version) VALUES (20260731180000);
INSERT INTO public.schema_migrations (version) VALUES (20260801000000);
INSERT INTO public.schema_migrations (version) VALUES (20260801000100);
INSERT INTO public.schema_migrations (version) VALUES (20260801000200);
INSERT INTO public.schema_migrations (version) VALUES (20260802000000);
INSERT INTO public.schema_migrations (version) VALUES (20260802000100);
INSERT INTO public.schema_migrations (version) VALUES (20260802000200);
INSERT INTO public.schema_migrations (version) VALUES (20260802000300);
INSERT INTO public.schema_migrations (version) VALUES (20260802000400);
INSERT INTO public.schema_migrations (version) VALUES (20260809000000);
INSERT INTO public.schema_migrations (version) VALUES (20260814211315);
INSERT INTO public.schema_migrations (version) VALUES (20260817010000);
INSERT INTO public.schema_migrations (version) VALUES (20260824000000);
INSERT INTO public.schema_migrations (version) VALUES (20260830000000);
INSERT INTO public.schema_migrations (version) VALUES (20260831000000);
INSERT INTO public.schema_migrations (version) VALUES (20260901000000);
INSERT INTO public.schema_migrations (version) VALUES (20260902000000);
INSERT INTO public.schema_migrations (version) VALUES (20260903000000);
INSERT INTO public.schema_migrations (version) VALUES (20260904000000);
INSERT INTO public.schema_migrations (version) VALUES (20260905000000);
INSERT INTO public.schema_migrations (version) VALUES (20260906000000);
INSERT INTO public.schema_migrations (version) VALUES (20260907000000);
