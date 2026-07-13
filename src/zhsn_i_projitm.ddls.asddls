@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Project Item - Interface'
define view entity ZHSN_I_ProjItm
  as select from zhsn_proj_itm
  association to parent ZHSN_I_ProjHdr as _Header
    on $projection.ProjUuid = _Header.ProjUuid
{
  key item_uuid             as ItemUuid,
      parent_uuid           as ProjUuid,
      project_id            as ProjectID,
      workpackage_id        as WorkPackageID,
      workpackage_name      as WorkPackageName,
      description           as Description,
      wp_start_date         as WPStartDate,
      wp_end_date           as WPEndDate,
unit_quantity        as UnitQty,
consumed_quantity     as ConsumeQty,
balance_quantity     as BalnacedQty,
tobe_billed_quantity as TobeBilledQty,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at       as LastChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,
      _Header
}
