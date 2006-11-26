<#--

Copyright 2001-2006 The Apache Software Foundation

Licensed under the Apache License, Version 2.0 (the "License"); you may not
use this file except in compliance with the License. You may obtain a copy of
the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.
-->
<#escape x as x?xml>
       <fo:table border-spacing="3pt">
           <fo:table-column column-width="3.75in"/>
          <fo:table-column column-width="3.75in"/>
          <fo:table-body>
            <fo:table-row>    <#-- this part could use some improvement -->
             
             <#-- a special purchased from address for Purchase Orders -->
             <#if orderHeader.getString("orderTypeId") == "PURCHASE_ORDER">
             <#if supplierGeneralContactMechValueMap?exists>
               <#assign contactMech = supplierGeneralContactMechValueMap.contactMech>
               <fo:table-cell>
                 <fo:block white-space-collapse="false">
<fo:block font-weight="bold">${uiLabelMap.OrderPurchasedFrom}:</fo:block><#assign postalAddress = supplierGeneralContactMechValueMap.postalAddress><#if postalAddress?has_content><#if postalAddress.toName?has_content>${postalAddress.toName}</#if><#if postalAddress.attnName?has_content>
${postalAddress.attnName?if_exists}</#if>
${postalAddress.address1?if_exists}<#if postalAddress.address2?has_content>
${postalAddress.address2?if_exists}</#if>
${postalAddress.city?if_exists}<#if postalAddress.stateProvinceGeoId?has_content>, ${postalAddress.stateProvinceGeoId} </#if></#if><#if postalAddress.postalCode?has_content>${postalAddress.postalCode}</#if>
${postalAddress.countryGeoId?if_exists}
</fo:block>
               </fo:table-cell>
             <#else>
               <#-- here we just display the name of the vendor, since there is no address -->
               <fo:table-cell>
                 <#assign vendorParty = orderReadHelper.getBillFromParty()>
                 <fo:block white-space-collapse="false">
<fo:block font-weight="bold">${uiLabelMap.OrderPurchasedFrom}:</fo:block>${Static['org.ofbiz.party.party.PartyHelper'].getPartyName(vendorParty)}
                 </fo:block>
               </fo:table-cell> 
             </#if>
             </#if>
             
             <#-- list all postal addresses of the order.  there should be just a billing and a shipping here. -->
             <#list orderContactMechValueMaps as orderContactMechValueMap>
               <#assign contactMech = orderContactMechValueMap.contactMech>
               <#assign contactMechPurpose = orderContactMechValueMap.contactMechPurposeType>
               <#if contactMech.contactMechTypeId == "POSTAL_ADDRESS">
               <fo:table-cell>
                 <fo:block white-space-collapse="false">
<fo:block font-weight="bold">${contactMechPurpose.get("description",locale)}: </fo:block><#assign postalAddress = orderContactMechValueMap.postalAddress><#if postalAddress?has_content><#if postalAddress.toName?has_content>${postalAddress.toName?if_exists}</#if><#if postalAddress.attnName?has_content>
${postalAddress.attnName?if_exists}</#if>
${postalAddress.address1?if_exists}<#if postalAddress.address2?has_content>
${postalAddress.address2?if_exists}</#if>
${postalAddress.city?if_exists}<#if postalAddress.stateProvinceGeoId?has_content>, ${postalAddress.stateProvinceGeoId} </#if></#if><#if postalAddress.postalCode?has_content>${postalAddress.postalCode}</#if>
</fo:block>
                </fo:table-cell>
                </#if>
             </#list>
             
            </fo:table-row>
         </fo:table-body>
       </fo:table>

       <fo:block white-space-collapse="false"> </fo:block> 

       <fo:table border-spacing="3pt">
          <fo:table-column column-width="1.75in"/>
          <fo:table-column column-width="4.25in"/>
          
  <#-- payment info -->                
          <fo:table-body>
           <#if orderPaymentPreferences?has_content>
            <fo:table-row>
                <fo:table-cell><fo:block>${uiLabelMap.AccountingPaymentInformation}</fo:block></fo:table-cell>
                <fo:table-cell><fo:block>
                      <#list orderPaymentPreferences as orderPaymentPreference>
                         <#assign paymentMethodType = orderPaymentPreference.getRelatedOne("PaymentMethodType")?if_exists>
                         <#if ((orderPaymentPreference != null) && (orderPaymentPreference.getString("paymentMethodTypeId") == "CREDIT_CARD") && (orderPaymentPreference.getString("paymentMethodId")?has_content))>
                           <#assign creditCard = orderPaymentPreference.getRelatedOne("PaymentMethod").getRelatedOne("CreditCard")>
                             ${Static["org.ofbiz.party.contact.ContactHelper"].formatCreditCard(creditCard)}
                         <#else>
                             ${paymentMethodType.get("description",locale)?if_exists}
                         </#if>
                      </#list>
                      </fo:block>
                 </fo:table-cell>
            </fo:table-row>
         </#if>
        
        <#-- shipping method.  currently not shown for PO's because we are not recording a shipping method for PO's in order entry -->
           <#if orderHeader.getString("orderTypeId") == "SALES_ORDER">
            <fo:table-row>
               <fo:table-cell><fo:block>${uiLabelMap.OrderShipmentInformation}:</fo:block></fo:table-cell>
                  <fo:table-cell>
                 <#if shipGroups?has_content>
                   <#list shipGroups as shipGroup>
                   <#-- TODO: List all full details of each ship group here -->
                        <fo:block>
                      ${shipGroup.shipmentMethodTypeId?if_exists}
                     </fo:block>
                   </#list>
                  </#if>
               </fo:table-cell>
             </fo:table-row>
           </#if>
       <#-- order terms information -->
             <#if orderTerms?has_content>
             <fo:table-row>
               <fo:table-cell><fo:block>${uiLabelMap.OrderOrderTerms}: </fo:block></fo:table-cell>
               <fo:table-cell white-space-collapse="false"><fo:block><#list orderTerms as orderTerm>${orderTerm.getRelatedOne("TermType").get("description",locale)} ${orderTerm.termValue?default("")} ${orderTerm.termDays?default("")}
</#list></fo:block></fo:table-cell>
             </fo:table-row>
             </#if>
          </fo:table-body>
       </fo:table>

<fo:block space-after="10pt"/>
</#escape>
