-- Ensure every ticket creator is automatically registered as a collaborator.
-- A trigger keeps this invariant independent of future create_ticket changes.

CREATE OR REPLACE FUNCTION public.add_ticket_creator_as_collaborator()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.ticket_collaborators (
        ticket_id,
        user_id,
        role,
        added_by
    )
    VALUES (
        NEW.id,
        NEW.created_by,
        'creator',
        NEW.created_by
    )
    ON CONFLICT (ticket_id, user_id)
    DO UPDATE SET
        role = 'creator',
        added_by = EXCLUDED.added_by;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_add_ticket_creator_as_collaborator
ON public.tickets;

CREATE TRIGGER trigger_add_ticket_creator_as_collaborator
AFTER INSERT ON public.tickets
FOR EACH ROW
EXECUTE FUNCTION public.add_ticket_creator_as_collaborator();

-- Backfill tickets created before this trigger existed.
INSERT INTO public.ticket_collaborators (
    ticket_id,
    user_id,
    role,
    added_by
)
SELECT
    id,
    created_by,
    'creator',
    created_by
FROM public.tickets
WHERE created_by IS NOT NULL
ON CONFLICT (ticket_id, user_id)
DO UPDATE SET
    role = 'creator',
    added_by = EXCLUDED.added_by;
