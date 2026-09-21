-- Allow sorting_clip events (cardboard / bulky packaging clips).

alter table public.vision_events
  drop constraint if exists vision_events_event_type_check;

alter table public.vision_events
  add constraint vision_events_event_type_check
  check (
    event_type in (
      'ppe_violation',
      'parking_entry',
      'parking_exit',
      'uniform_violation',
      'sorting_clip'
    )
  );

alter table public.vision_cameras
  drop constraint if exists vision_cameras_event_type_check;

alter table public.vision_cameras
  add constraint vision_cameras_event_type_check
  check (
    event_type in (
      'ppe_violation',
      'parking_entry',
      'parking_exit',
      'uniform_violation',
      'sorting_clip'
    )
  );
