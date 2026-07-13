@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Project Header - Interface'
define root view entity ZHSN_I_ProjHdr
  as select from zhsn_proj_hdr
  composition [0..*] of ZHSN_I_ProjItm as _Item
{
  key proj_uuid              as ProjUuid,
  @EndUserText.label: 'ProjectID'
      project_id             as ProjectID,
//      project_name           as ProjectName,
@EndUserText.label: 'Project Name'
      project_name           as ProjectName,
//      project_stage          as ProjectStage,
//      org_id                 as OrgID,
      @EndUserText.label: 'Project Stage'
      project_stage          as ProjectStage,
      @EndUserText.label: 'Org ID'
      org_id                 as OrgID,
      //@Semantics.amount.currencyCode: 'Currency'
      @EndUserText.label: 'Currency'
      currency               as Currency,
      @EndUserText.label: 'Customer'
      customer               as Customer,
      @EndUserText.label: 'CostCenter'
      cost_center            as CostCenter,
      @EndUserText.label: 'ProfitCenter'
      profit_center          as ProfitCenter,
      @EndUserText.label: 'StartDate'
      start_date             as StartDate,
      @EndUserText.label: 'EndDate'
      end_date               as EndDate,
      @EndUserText.label: 'ProjectDesc'
      project_desc           as ProjectDesc,
      @Semantics.user.createdBy: true
      created_by             as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at             as CreatedAt,
      @Semantics.user.lastChangedBy: true
      last_changed_by        as LastChangedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at        as LastChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at  as LocalLastChangedAt,
      @Semantics.largeObject: { mimeType: 'MimeType',
                                fileName: 'FileName',
                                contentDispositionPreference: #ATTACHMENT }
      attachment             as Attachment,
      mimetype               as MimeType,
      filename               as FileName,
      @EndUserText.label: 'ReferenceDocument'
      reference_document as ReferenceDocument,
      @EndUserText.label: 'AllocStatus'
      alloc_status       as AllocStatus,
      alloc_response     as AllocResponse,
      _Item
}
